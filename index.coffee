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
]

parseArgv = (argv) ->
  config = "#{process.cwd()}/.stack-deploy"
  dfault = JSON.parse readFileSync config if fs.existsSync config
  opts = getopts argv, {
    alias:
      bucket:     'b'
      create:     'c'
      help:       'h'
      linter:     'l'
      profile:    'p'
      parameters: 'P'
      quiet:      'q'
      region:     'r'
      tmpdir:     'd'
      verbose:    'v'
      yes:        'y'
    boolean: [
      'create'
      'help'
      'quiet'
      'verbose'
      'yes'
    ]
    string: [
      'bucket'
      'linter'
      'parameters'
      'profile'
      'region'
      'tmpdir'
    ]
    default: Object.assign {tmpdir}, dfault
    unknown: (x) -> abort "unknown option: '#{x}'"
  }
  opts.template = opts._[0]
  opts.stackname = opts._[1]
  opts.s3bucket = opts.bucket

  Object.assign {}, (if fs.existsSync config then JSON.parse readFileSync config), opts

generateAwsCommand = (profile, region) ->
  parg = if profile then "--profile '#{profile}'" else ''
  rarg = if region then "--region '#{region}'" else ''
  "aws #{parg} #{rarg}".replace(/ +/g, ' ').trimRight()

parseAwsVersion = (x) ->
  Number (x or '').split(/ /)?[0].split(/\//)?[1].split(/[.]/)?[0]

module.exports = () ->
  opts = parseArgv(process.argv.slice(2))
  cfn  = new CfnTransformer(opts)
  exec = cfn.execShell.bind(cfn)
  args = cfn.execShellArgs.bind(cfn)

  log.level = switch
    when opts.verbose then 'verbose'
    when opts.quiet   then 'error'
    else                   'info'

  assertOk opts.template, 'template argument required'
  assertOk exec 'which aws', 'aws CLI tool not found on $PATH' if opts.stackname

  cfn.aws         = generateAwsCommand opts.profile, opts.region
  cfn.awsversion  = parseAwsVersion exec "#{cfn.aws} --version"

  assertOk cfn.awsversion in AWS_VERSIONS,
    "unsupported aws CLI tool version: #{cfn.awsversion} (supported versions are #{AWS_VERSIONS})"

  log.info 'transforming templates...'

  res = cfn.writeTemplate(opts.template)
  tpl = readFileSync(res.tmpPath).toString('utf-8')

  if not opts.stackname
    console.log tpl
  else if res.nested.length and not opts.bucket
    throw new CfnError('bucket required for nested stacks')
  else
    log.info "doing more stuff..."

  process.exit(0)
