fs                  = require 'fs'
os                  = require 'os'
path                = require 'path'
uuid                = require 'uuid'
{inspect}           = require 'util'
getopts             = require 'getopts'
yaml                = require 'js-yaml'
{strict: assert}    = require 'assert'
log                 = require './lib/log'
CfnError            = require './lib/CfnError'
CfnTransformer      = require './lib/cfn-transformer'
{version: VERSION}  = require './package.json'
AWS_VERSIONS        = [1, 2]

identity = (x) -> x

assoc = (xs, k, v) ->
  xs[k] = v
  xs

selectKeys = (o, ks) ->
  Object.keys(o).reduce(((xs, x) -> if x in ks then assoc(xs, x, o[x]) else xs), {})

split = (str, sep, count=Infinity) ->
  toks  = str.split(sep)
  n     = Math.min(toks.length, count) - 1
  toks[0...n].concat(toks[n..].join(sep))

assertOk = (x, msg, body) ->
  throw new CfnError(msg, body) unless x
  x

quit = (msg) ->
  console.log msg if msg
  process.exit 0

abort = (e) ->
  e = new CfnError(e.message) if e.code is 'ENOENT'
  body = if e instanceof CfnError then e.body else e.body or e.stack
  log.error(e.message, {body})
  process.exit 1

process.on 'uncaughtException', abort

typeOf = (thing) ->
  Object::toString.call(thing).slice(8,-1)

abortOnException = (lib, fn) ->
  (if typeOf(fn) is 'Array' then fn else [fn]).forEach (x) ->
    global[x] = (args...) ->
      try
        lib[x].apply(lib, args)
      catch e
        abort(e)

abortOnException fs, [
  'writeFileSync'
  'readFileSync'
  'existsSync'
]

fixRegion = () ->
  [r1, r2] = [process.env.AWS_REGION, process.env.AWS_DEFAULT_REGION]
  process.env.AWS_REGION          = r2 if r1 and r2 and r1 isnt r2
  process.env.AWS_REGION          = r2 if r2 and not r1
  process.env.AWS_DEFAULT_REGION  = r1 if r1 and not r2

fixRegion()

getoptsConfig =
  alias:
    bucket:     'b'
    config:     'c'
    help:       'h'
    keep:       'k'
    linter:     'l'
    parameters: 'P'
    profile:    'p'
    quiet:      'q'
    region:     'r'
    tags:       't'
    verbose:    'v'
    version:    'V'
  boolean: [
    'help'
    'keep'
    'quiet'
    'verbose'
    'version'
  ]
  string: [
    'bucket'
    'config'
    'linter'
    'parameters'
    'profile'
    'region'
    'tags'
  ]
  unknown: (x) -> abort new CfnError("unknown option: '#{x}'")

opt2var =
  bucket:     'CFN_TOOL_BUCKET'
  config:     'CFN_TOOL_CONFIG'
  help:       'CFN_TOOL_HELP'
  keep:       'CFN_TOOL_KEEP'
  linter:     'CFN_TOOL_LINTER'
  parameters: 'CFN_TOOL_PARAMETERS'
  profile:    'AWS_PROFILE'
  quiet:      'CFN_TOOL_QUIET'
  region:     'AWS_REGION'
  tags:       'CFN_TOOL_TAGS'
  verbose:    'CFN_TOOL_VERBOSE'
  version:    'CFN_TOOL_VERSION'

assert.deepEqual new Set(Object.keys(opt2var)),
  new Set(getoptsConfig.boolean.concat(getoptsConfig.string)),
  "option->variable name mapping out of sync"

var2opt = Object.keys(opt2var).reduce(((xs, x) -> assoc xs, opt2var[x], x), {})
allOpts = Object.keys(opt2var)
allVars = Object.keys(var2opt)
useVars = Object.keys(var2opt).reduce(
  (xs, x) -> if process.env[x]? then xs.concat [x] else xs
  []
)

config2opt = (k, v) ->
  if not (k in getoptsConfig.boolean) then v else (v is 'true')

getVars = () ->
  allOpts.reduce(
    (xs, x) ->
      v = process.env[opt2var[x]]
      if v? then assoc(xs, x, config2opt(x, v)) else xs
    {}
  )

setVars = (opts, clobber=false) ->
  for o, v of opt2var
    process.env[v] = "#{opts[o]}" if opts[o]? and (clobber or not (v in useVars))
  fixRegion()

usage = () ->
  quit """
    See the manpage:
    * cmd: man cfn-tool
    * url: http://htmlpreview.github.io/?https://github.com/daggerml/cfn-tool/blob/#{VERSION}/man/cfn-tool.1.html
  """

version = () ->
  quit VERSION

parseArgv = (argv) ->
  opts  = getopts argv, assoc getoptsConfig, 'default', getVars()

  switch
    when opts.help then usage()
    when opts.version then version()
    when not argv.length then usage()

  opts.template   = opts._[0]
  opts.stackname  = opts._[1]

  assertOk opts.template, 'template argument required'

  if not opts.stackname
    Object.assign opts,
      debug:      true
      bucket:     'example-bucket'
      s3bucket:   'example-bucket'
  else
    Object.assign opts,
      dolint:     true
      dovalidate: true
      dopackage:  true
      s3bucket:   opts.bucket

  opts

parseAwsVersion = (x) ->
  Number x?.match(/^aws-cli\/([0-9]+)\./)?[1]

parseKeyValArg = (x) ->
  x.split(/ /).map((x) -> "'#{x}'").join(' ')

parseConfig = (x, uid) ->
  lines = x.split('\n').map((x) -> x.trim()).filter(identity)
  lines = lines.slice(lines.indexOf(uid) + 2)
  lines.reduce(
    (xs, line) ->
      [k, v] = split(line, '=', 2)
      k = var2opt[k]
      v = Buffer.from(v, 'base64').toString('utf-8')
      if k then assoc(xs, k, config2opt(k, v)) else xs
    {}
  )

setLogLevel = (opts) ->
  log.level = switch
    when opts.verbose then 'verbose'
    when opts.quiet   then 'error'
    when opts.debug   then 'warn'
    else              'info'
  opts

module.exports = () ->
  opts  = setLogLevel parseArgv process.argv.slice(2)
  cfn   = new CfnTransformer opts
  exec  = cfn.execShell.bind cfn
  cfg   = opts.config or (existsSync('.cfn-tool') and '.cfn-tool')
  uid   = uuid.v4()

  if cfg
    log.verbose "using config file: #{cfg}"
    setVars opts
    cfgscript = readFileSync(cfg)
    try
      setVars parseConfig exec """
        . '#{cfg}'
        echo
        echo #{uid}
        for i in $(compgen -A variable |grep '^\\(AWS_\\|CFN_TOOL_\\)'); do
          echo $i=$(echo -n "${!i}" |base64 -w0)
        done
      """
    catch e
      e.message = e.message.split('\n').shift()
      throw e
    opts  = setLogLevel parseArgv process.argv.slice(2)
    cfn   = new CfnTransformer opts
    exec  = cfn.execShell.bind cfn

  setVars opts, true

  cfn.tmpdir = fs.mkdtempSync([os.tmpdir(), 'cfn-tool-'].join('/'))
  process.on 'exit', () -> fs.rmdirSync cfn.tmpdir, {recursive: true} unless opts.keep

  log.verbose "configuration options", {body: inspect selectKeys(opts, allOpts)}

  assertOk exec 'which aws', 'aws CLI tool not found on $PATH' if opts.stackname
  awsversion = parseAwsVersion(exec('aws --version'))
  assertOk awsversion in AWS_VERSIONS,
    "unsupported aws CLI tool version: #{awsversion} (supported versions are #{AWS_VERSIONS})"

  log.info 'preparing templates'

  res = cfn.writeTemplate(opts.template)
  tpl = readFileSync(res.tmpPath).toString('utf-8')

  if opts.debug
    console.log tpl.trimRight()
  else if opts.stackname
    if res.nested.length > 1
      throw new CfnError('bucket required for nested stacks') unless opts.bucket
      log.info 'uploading templates to S3'
      exec "aws s3 sync --size-only '#{cfn.tmpdir}' 's3://#{opts.bucket}/'"

    bucketarg = "--s3-bucket '#{opts.bucket}' --s3-prefix aws/"           if opts.bucket
    paramsarg = "--paramter-overrides #{parseKeyValArg(opts.parameters)}" if opts.parameters
    tagsarg   = "--tags #{parseKeyValArg(opts.tags)}"                     if opts.tags

    log.info 'deploying stack'
    exec """
      aws cloudformation deploy \
        --template-file '#{res.tmpPath}' \
        --stack-name '#{opts.stackname}' \
        --capabilities CAPABILITY_NAMED_IAM CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
        #{bucketarg or ''} #{paramsarg or ''} #{tagsarg or ''}
    """

  log.info 'done -- no errors'
  quit()
