yaml            = require 'js-yaml'
assert          = require 'assert'
fs              = require 'fs'
os              = require 'os'
path            = require 'path'
{execSync}      = require 'child_process'
fn              = require '../lib/fn'
log             = require '../lib/log'
CfnTransformer  = require '../lib/cfn-transformer'
tmpdir          = fs.mkdtempSync([os.tmpdir(), 'cfn-tool-'].join('/'))

process.on 'exit', () ->
  fs.rmdirSync opts.tmpdir, {recursive: true}
  try fs.unlinkSync "#{__dirname}/data/data2.txt" catch e

process.env.ZONE            = 'test'
process.env.REGION          = 'us-east-1'
process.env.MY_ENV_VAR      = 'myval'
process.env.CFN_TOOL_BUCKET = 'test-bucket'

opts =
  tmpdir:     tmpdir
  s3bucket:   'foop'
  dopackage:  true

testCase = (file) ->
  #cases     = yaml.safeLoad(xf.transformFile(file))
  text      = fs.readFileSync(file).toString('utf-8')
  cases     = new CfnTransformer({opts}).parse(text)
  for k, v of cases
    do (k = k, v = v) ->
      it k, ->
        xf = new CfnTransformer({opts})
        v  = yaml.safeLoad(xf.transformFile(file, v))
        if v.throws
          f = () -> new CfnTransformer({opts}).transformFile(file, v.template)
          assert.throws f, new RegExp(v.throws)
        else
          assert(v.template and v.expected, JSON.stringify(v))
          assert.deepEqual(v.template, v.expected)
          assert.deepEqual(xf.nested.slice(1), v.nested or [])

for f in fs.readdirSync(__dirname, {withFileTypes: true})
  if f.isFile() and f.name.match(/\.(yml|yaml)$/)
    describe "#{f.name.split('.').shift()} tests", -> testCase("#{__dirname}/#{f.name}")
