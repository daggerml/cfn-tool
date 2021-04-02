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

objKeys = (x) -> Object.keys(x)
objVals = (x) -> objKeys(x).reduce(((ys, y) -> ys.concat([x[y]])), [])

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
  throw e
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

defaultOptionsSpec =
  alias:
    help:     'h'
    version:  'V'
  boolean:    ['help', 'version']
  string:     []
  unknown:    (x) -> abort new CfnError("unknown option: '#{x}'")

optionsSpecs =
  deploy:
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
  transform:
    alias:
      config:     'c'
      help:       'h'
      linter:     'l'
      profile:    'p'
      quiet:      'q'
      region:     'r'
      verbose:    'v'
      version:    'V'
    boolean: [
      'help'
      'quiet'
      'verbose'
      'version'
    ]
    string: [
      'config'
      'linter'
      'profile'
      'region'
    ]
    unknown: (x) -> abort new CfnError("unknown option: '#{x}'")
  update:
    alias:
      config:     'c'
      help:       'h'
      parameters: 'P'
      profile:    'p'
      quiet:      'q'
      region:     'r'
      verbose:    'v'
      version:    'V'
    boolean: [
      'help'
      'quiet'
      'verbose'
      'version'
    ]
    string: [
      'config'
      'parameters'
      'profile'
      'region'
    ]
    unknown: (x) -> abort new CfnError("unknown option: '#{x}'")

getoptsConfig = optionsSpecs[process.argv[2]] or defaultOptionsSpec

opt2var =
  profile:    'AWS_PROFILE'
  region:     'AWS_REGION'

opt2var = getoptsConfig.boolean.concat(getoptsConfig.string).reduce(
  (xs, x) -> assoc(xs, x, opt2var[x] or "CFN_TOOL_#{x.toUpperCase()}")
  {}
)

allCmds = Object.keys(optionsSpecs)
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

setVars = (opts, {clobber = false} = {}) ->
  for o, v of opt2var
    process.env[v] = "#{opts[o]}" if opts[o]? and (clobber or not (v in useVars))
  fixRegion()

usage = (command) ->
  x = ['cfn-tool'].concat(if command then [command] else []).join('-') 
  quit """
    See the manpage:
    * cmd: man #{x}
    * url: http://htmlpreview.github.io/?https://github.com/daggerml/cfn-tool/blob/#{VERSION}/man/#{x}.html
  """

version = () ->
  quit VERSION

parseArgv = (argv) ->
  opts  = getopts argv, assoc getoptsConfig, 'default', getVars()

  [command, args...]  = opts._ or []
  Object.assign(opts, {command, args})

  assertOk(not command or command in allCmds, "unknown command: '#{command}'")

  switch
    when opts.help then usage(command)
    when opts.version then version()

  opts

parseAwsVersion = (x) ->
  Number x?.match(/^aws-cli\/([0-9]+)\./)?[1]

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
    else              'info'
  opts

module.exports = () ->
  opts  = setLogLevel parseArgv process.argv.slice(2)
  cfn   = new CfnTransformer {opts}
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
    opts = cfn.opts = setLogLevel parseArgv process.argv.slice(2)

  setVars opts, {clobber: true}

  opts.tmpdir = fs.mkdtempSync([os.tmpdir(), 'cfn-tool-'].join('/'))
  process.on 'exit', () -> fs.rmdirSync opts.tmpdir, {recursive: true} unless opts.keep

  log.verbose "configuration options", {body: inspect selectKeys(opts, allOpts)}

  assertOk exec 'which aws', 'aws CLI tool not found on $PATH'
  awsversion = parseAwsVersion(exec('aws --version'))
  assertOk awsversion in AWS_VERSIONS,
    "unsupported aws CLI tool version: #{awsversion} (supported versions are #{AWS_VERSIONS})"

  switch opts.command

    when 'transform'
      Object.assign opts,
        template:   opts.args[0]
        dovalidate: false
        dopackage:  false
        bucket:     'example-bucket'
        s3bucket:   'example-bucket'

      assertOk opts.template, 'template argument required'

      log.verbose 'preparing template'
      res = cfn.writeTemplate(opts.template)
      tpl = readFileSync(res.tmpPath).toString('utf-8')

      console.log tpl.trimRight()

    when 'deploy'
      Object.assign opts,
        template:   opts.args[0]
        stackname:  opts.args[1]
        dovalidate: true
        dopackage:  true
        s3bucket:   opts.bucket

      assertOk opts.template, 'template argument required'
      assertOk opts.stackname, 'stackname argument required'

      log.info 'preparing templates'
      res = cfn.writeTemplate(opts.template)
      tpl = readFileSync(res.tmpPath).toString('utf-8')

      if res.nested.length > 1
        throw new CfnError('bucket required for nested stacks') unless opts.bucket
        log.info 'uploading templates to S3'
        exec "aws s3 sync --size-only '#{cfn.tmpdir}' 's3://#{opts.bucket}/'"

      bucketarg = "--s3-bucket '#{opts.bucket}' --s3-prefix aws/" if opts.bucket
      paramsarg = "--parameter-overrides #{opts.parameters}"      if opts.parameters
      tagsarg   = "--tags #{opts.tags}"                           if opts.tags

      log.info 'deploying stack'
      exec """
        aws cloudformation deploy \
          --template-file '#{res.tmpPath}' \
          --stack-name '#{opts.stackname}' \
          --capabilities CAPABILITY_NAMED_IAM CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
          #{bucketarg or ''} #{paramsarg or ''} #{tagsarg or ''}
      """

      log.info 'done -- no errors'

    when 'update'
      opts.stackname = opts.args[0]
      assertOk opts.stackname, 'stackname argument required'

      res = JSON.parse exec """
        aws cloudformation describe-stacks --stack-name '#{opts.stackname}'
      """

      params = res?.Stacks?[0]?.Parameters?.reduce(
        (xs, x) ->
          k = x.ParameterKey
          assoc xs, k, "ParameterKey=#{k},UsePreviousValue=true"
        {}
      )
      assertOk Object.keys(params).length, "stack '#{opts.stackname}' has no parameters"

      haveOverride = null
      for x in (opts.parameters?.split(/ +/) or [])
        [k, v] = split(x, '=', 2)
        assertOk k and v, "parameter: expected <key>=<value>: got '#{x}'"
        assertOk params[k], "stack '#{opts.stackname}' has no parameter '#{k}'"
        haveOverride = params[k] = "ParameterKey=#{k},ParameterValue=#{v}"

      assertOk haveOverride, 'parameter overrides required'

      paramsarg = objVals(params).join(' ')

      exec """
        aws cloudformation update-stack \
          --stack-name #{opts.stackname} \
          --parameters #{paramsarg} \
          --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
          ----use-previous-template
      """

      log.info 'done -- no errors'

  quit()
