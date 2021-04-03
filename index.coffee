fs                  = require 'fs'
os                  = require 'os'
path                = require 'path'
{inspect}           = require 'util'
GetOpts             = require './lib/GetOpts'
yaml                = require 'js-yaml'
{strict: assert}    = require 'assert'
fn                  = require './lib/fn'
log                 = require './lib/log'
CfnError            = require './lib/CfnError'
CfnTransformer      = require './lib/cfn-transformer'
{version: VERSION}  = require './package.json'
AWS_VERSIONS        = [1, 2]

quit = (msg, status = 0) ->
  console.log msg if msg
  process.exit status

abort = (e) ->
  e = new CfnError(e.message) if e.code is 'ENOENT'
  body = if e instanceof CfnError then e.body else e.body or e.stack
  log.error(e.message, {body})
  process.exit 1

process.on 'uncaughtException', abort

fn.abortOnException abort, fs, [
  'writeFileSync'
  'readFileSync'
  'existsSync'
]

getopts = new GetOpts(
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
  string:
    bucket:     '<name>'
    config:     '<file>'
    linter:     '<command>'
    parameters: '"<key>=<val> ..."'
    profile:    '<name>'
    region:     '<name>'
    tags:       '"<key>=<val> ..."'
  positional:
    command:    null
    template:   '<template-file>'
    stackname:  '<stack-name>'
  opt2var: (opt) ->
    switch opt
      when 'profile' then 'AWS_PROFILE'
      when 'region' then 'AWS_REGION'
      else "CFN_TOOL_#{opt.toUpperCase()}"
  unknown: (x) -> abort new CfnError("unknown option: '#{x}'")
)

defaultOptionsSpec = [
  'help'
  'version'
  'command'
]

optionsSpecs =
  deploy: [
    'bucket'
    'config'
    'help'
    'keep'
    'linter'
    'parameters'
    'profile'
    'quiet'
    'region'
    'tags'
    'verbose'
    'command'
    'template'
    'stackname'
  ]
  transform: [
    'config'
    'help'
    'linter'
    'profile'
    'quiet'
    'region'
    'tags'
    'verbose'
    'command'
    'template'
  ]
  update: [
    'config'
    'help'
    'parameters'
    'profile'
    'quiet'
    'region'
    'verbose'
    'command'
    'stackname'
  ]

do (spec = optionsSpecs[process.argv[2]]) ->
  if spec then getopts.configure(spec)
  else getopts.configure(defaultOptionsSpec, false)

allCmds = Object.keys(optionsSpecs)

usageCmd = (cmd) ->
  getopts.configure(if cmd then optionsSpecs[cmd] else defaultOptionsSpec)
  prog  = path.basename(process.argv[1])
  lpad  = (x) -> "  #{x}"
  opts  = getopts.usage().map(lpad).join("\n")
  "#{prog}#{if cmd then " #{cmd}" else ''}#{if opts then "\n#{opts}" else ''}"

usage = (cmd, status) ->
  prog  = path.basename(process.argv[1])
  manp  = [prog].concat(if cmd then [cmd] else []).join('-')
  text  = if cmd then usageCmd(cmd) else [null].concat(allCmds).map(usageCmd).join("\n\n")
  quit """
    #{text}

    See the manpage:
    * cmd: man #{manp}
    * url: http://htmlpreview.github.io/?https://github.com/daggerml/cfn-tool/blob/#{VERSION}/man/#{manp}.html
  """, status

version = () ->
  quit VERSION

parseArgv = (argv) ->
  opts  = getopts.parse argv
  cmd   = opts.command
  fn.assertOk(cmd in allCmds, "unknown command: '#{cmd}'") if cmd
  switch
    when opts.help then usage(cmd)
    when opts.version then version()
    when not cmd then usage(null, 1)
  getopts.validateArgs(opts)
  opts

parseAwsVersion = (x) ->
  Number x?.match(/^aws-cli\/([0-9]+)\./)?[1]

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

  if cfg
    log.verbose "using config file: #{cfg}"
    try
      getopts.loadConfig exec, opts, cfg
    catch e
      e.message = e.message.split('\n').shift()
      throw e
    opts = cfn.opts = setLogLevel parseArgv process.argv.slice(2)

  getopts.setVars opts, {clobber: true}

  opts.tmpdir = fs.mkdtempSync([os.tmpdir(), 'cfn-tool-'].join('/'))
  process.on 'exit', () -> fs.rmdirSync opts.tmpdir, {recursive: true} unless opts.keep

  log.verbose "configuration options", {body: inspect fn.selectKeys(opts, getopts.allOpts())}

  fn.assertOk exec 'which aws', 'aws CLI tool not found on $PATH'
  awsversion = parseAwsVersion(exec('aws --version'))
  fn.assertOk awsversion in AWS_VERSIONS,
    "unsupported aws CLI tool version: #{awsversion} (supported versions are #{AWS_VERSIONS})"

  switch opts.command

    when 'transform'
      Object.assign opts,
        dovalidate: false
        dopackage:  false
        bucket:     'example-bucket'
        s3bucket:   'example-bucket'

      fn.assertOk opts.template, 'template argument required'

      log.verbose 'preparing template'
      res = cfn.writeTemplate(opts.template)
      tpl = readFileSync(res.tmpPath).toString('utf-8')

      console.log tpl.trimRight()

    when 'deploy'
      Object.assign opts,
        dovalidate: true
        dopackage:  true
        s3bucket:   opts.bucket

      fn.assertOk opts.template, 'template argument required'
      fn.assertOk opts.stackname, 'stackname argument required'

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
      fn.assertOk opts.stackname, 'stackname argument required'

      res = JSON.parse exec """
        aws cloudformation describe-stacks --stack-name '#{opts.stackname}'
      """

      params = res?.Stacks?[0]?.Parameters?.reduce(
        (xs, x) ->
          k = x.ParameterKey
          fn.assoc xs, k, "ParameterKey=#{k},UsePreviousValue=true"
        {}
      )
      fn.assertOk Object.keys(params).length, "stack '#{opts.stackname}' has no parameters"

      haveOverride = null
      for x in (opts.parameters?.split(/ +/) or [])
        [k, v] = fn.split(x, '=', 2)
        fn.assertOk k and v, "parameter: expected <key>=<value>: got '#{x}'"
        fn.assertOk params[k], "stack '#{opts.stackname}' has no parameter '#{k}'"
        haveOverride = params[k] = "ParameterKey=#{k},ParameterValue=#{v}"

      fn.assertOk haveOverride, 'parameter overrides required'

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
