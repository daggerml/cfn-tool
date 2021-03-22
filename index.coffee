fs                = require 'fs'
os                = require 'os'
path              = require 'path'
getopts           = require 'getopts'
yaml              = require 'js-yaml'
log               = require './lib/log'
CfnError          = require './lib/CfnError'
CfnTransformer    = require './lib/cfn-transformer'
tmpdir            = fs.mkdtempSync([os.tmpdir(), 'stack-deploy-'].join('/'))
AWS_VERSIONS      = [1, 2]

assertOk = (x, msg, body) ->
  throw new CfnError(msg, body) unless x
  x

abort = (e) ->
  e = new CfnError(e.message) if e.code is 'ENOENT'
  body = if e instanceof CfnError then e.body else e.body or e.stack
  log.error(e.message, {body})
  process.exit 1

process.on 'exit', () -> fs.rmdirSync tmpdir, {recursive: true}
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

getoptsBaseConfig =
  alias:      {help: 'h'}
  boolean:    ['help']
  string:     []
  default:    {}
  stopEarly:  true

getoptsConfig =

  transform:
    alias:
      config:     'c'
      quiet:      'q'
      verbose:    'v'
    boolean: [
      'config'
      'quiet'
      'verbose'
    ]
    string: []
    default: {}

  deploy:
    alias:
      bucket:     'b'
      config:     'c'
      linter:     'l'
      parameters: 'P'
      profile:    'p'
      quiet:      'q'
      region:     'r'
      tags:       't'
      verbose:    'v'
    boolean: [
      'quiet'
      'verbose'
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

commands = Object.keys(getoptsConfig)

usage = () ->
  console.log "USAGE HERE"
  process.exit(0)

parseArgv = (argv) ->
  usage() if argv[0] in ['-h', '--help']
  dfl           = {bucket: process.env.CFN_TOOL_BUCKET}
  unknown       = (x) -> abort new CfnError("unknown option: '#{x}'")
  mkconfig      = (x, y) -> Object.assign({unknown, default: dfl}, y or getoptsConfig[x])
  opts          = getopts argv, mkconfig(null, getoptsBaseConfig)
  argv          = opts._
  opts          = if opts.help or not argv[0] then usage() else {command: argv.shift()}

  assertOk opts.command in commands, "command required (one of: #{commands})"
  Object.assign opts, getopts(argv, mkconfig(opts.command))

  opts.template   = opts._[0]
  opts.stackname  = opts._[1]

  assertOk opts.template, 'template argument required'

  if opts.command is 'deploy'
    Object.assign opts,
      tmpdir:     tmpdir
      dolint:     true
      dovalidate: true
      doaws:      true
      s3bucket:   opts.bucket

  opts

generateAwsCommand = (profile, region) ->
  parg = if profile then "--profile '#{profile}'" else ''
  rarg = if region then "--region '#{region}'" else ''
  "aws #{parg} #{rarg}".replace(/ +/g, ' ').trimRight()

parseAwsVersion = (x) ->
  Number x?.match(/^aws-cli\/([0-9]+)\./)?[1]

parseKeyValArg = (x) ->
  x.split(/,/).map((x) -> "'#{x}'").join(' ')

module.exports = () ->
  [r1, r2] = [process.env.AWS_REGION, process.env.AWS_DEFAULT_REGION]
  r1   = r2 if r2 and not r1
  r2   = r1 if r1 and not r2
  opts = parseArgv(process.argv.slice(2))
  cfn  = new CfnTransformer(opts)
  exec = cfn.execShell.bind(cfn)
  args = cfn.execShellArgs.bind(cfn)

  log.level = switch
    when opts.verbose                 then 'verbose'
    when opts.quiet                   then 'error'
    when opts.command is 'transform'  then 'warn'
    else                              'info'

  if opts.doaws
    assertOk exec 'which aws', 'aws CLI tool not found on $PATH' if opts.stackname
    cfn.aws         = generateAwsCommand opts.profile, opts.region
    cfn.awsversion  = parseAwsVersion exec 'aws --version'
    assertOk cfn.awsversion in AWS_VERSIONS,
      "unsupported aws CLI tool version: #{cfn.awsversion} (supported versions are #{AWS_VERSIONS})"

  log.info 'preparing templates...'

  res = cfn.writeTemplate(opts.template)
  tpl = readFileSync(res.tmpPath).toString('utf-8')

  switch opts.command
    when 'transform'
      console.log tpl.trimRight()
    when 'deploy'
      break unless opts.stackname

      if res.nested.length
        throw new CfnError('bucket required for nested stacks') unless opts.bucket
        log.info 'uploading templates to S3...'
        exec "#{cfn.aws} sync --size-only '#{opts.tmpdir}' 's3://#{opts.bucket}/cfn-tool/'"

      bucketarg = "--s3-bucket '#{opts.bucket}' --s3-prefix aws/"   if opts.bucket
      paramsarg = "--paramter-overrides #{parseKeyValArg(opts.parameters)}" if opts.parameters
      tagsarg   = "--tags #{parseKeyValArg(opts.tags)}"                     if opts.tags

      log.info 'deploying stack...'
      exec """
        #{cfn.aws} cloudformation deploy \
          --template-file '#{res.tmpPath}' \
          --stack-name '#{opts.stackname}' \
          --capabilities CAPABILITY_NAMED_IAM CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
          #{bucketarg or ''} #{paramsarg or ''} #{tagsarg or ''}
      """

  log.info 'done'
  process.exit(0)
