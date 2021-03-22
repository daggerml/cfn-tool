yaml            = require 'js-yaml'
assert          = require 'assert'
fs              = require 'fs'
path            = require 'path'
{execSync}      = require 'child_process'
CfnTransformer  = require '../../lib/cfn-transformer'

execShell = (command, opts) ->
  try
    execSync(command, Object.assign({stdio: 'pipe'}, opts)).toString('utf-8').trim()
  catch e
    msg = "shell exec failed: #{command}"
    err = e.stderr.toString('utf-8')
    assert.fail(if err? then "#{msg}\n#{err}" else msg)

s3bucket = 'foop'

process.env.ZONE            = 'test'
process.env.REGION          = 'us-east-1'
process.env.MY_ENV_VAR      = 'myval'
process.env.CFN_TOOL_BUCKET = 'test-bucket'

testCase = (file) ->
  #cases     = yaml.safeLoad(xf.transformFile(file))
  text      = fs.readFileSync(file).toString('utf-8')
  cases     = new CfnTransformer({s3bucket}).parse(text)
  for k, v of cases
    do (k = k, v = v) ->
      it k, ->
        xf = new CfnTransformer({s3bucket})
        v  = yaml.safeLoad(xf.transformFile(file, v))
        assert(v.template and v.expected, JSON.stringify(v))
        assert.deepEqual(v.template, v.expected)

for f in fs.readdirSync(__dirname, {withFileTypes: true})
  if f.isFile() and f.name.match(/\.(yml|yaml)$/)
    describe f.name.split('.').shift(), -> testCase("#{__dirname}/#{f.name}")