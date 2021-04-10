assert              = require 'assert'
fn                  = require '../lib/fn'
CfnTool             = require '../'

makeLogs = (tool) ->
  addLog = (xs, {level, message}) ->
    fn.assoc(xs, level, (xs[level] or []).concat([message.trim()]))
  tool.logs = tool.sideEffects.reduce(addLog, {})

cfn_tool = module.exports.cfn_tool = (args=[], env={}) ->
  tool = new CfnTool()
  makeLogs tool.test(-> tool.cli([null, null].concat(args), env))
  tool

cfn_complete = module.exports.cfn_complete = (args=[], env={}) ->
  tool = new CfnTool()
  makeLogs tool.test(-> tool.complete([null, null].concat(args), env))
  tool

assertLog = module.exports.assertLog = (tool, level, message) ->
  op  = if message? then 'notEqual' else 'equal'
  err = if message? then 'expected log' else 'unexpected log'
  assert[op] (tool.logs[level] or []).indexOf(message), -1, "#{err}: #{level}: #{message}"

assertExit = module.exports.assertExit = (tool, status) ->
  assert.equal(tool.exitStatus, status)

assertOpt = module.exports.assertOpt = (tool, k, v) ->
  assert.equal tool.opts[k], v

assertEnv = module.exports.assertEnv = (tool, k, v) ->
  assert.equal tool.env[k], v

assertShell = module.exports.assertShell = (tool, cmd) ->
  assertLog tool, 'spawn', cmd

assertResult = module.exports.assertResult = (tool, result) ->
  assertLog tool, 'console', result

assertInfo = module.exports.assertInfo = (tool, message) ->
  assertLog tool, 'info', message

assertVerbose = module.exports.assertVerbose = (tool, message) ->
  assertLog tool, 'verbose', message

assertError = module.exports.assertError = (tool, message) ->
  assertLog tool, 'error', message

fn.mockShell 'aws configure list-profiles',
  status: 0
  stdout: """
    default
    foop
    barp
  """

fn.mockShell "aws cloudformation describe-stacks --stack-name 'mystack'",
  status: 0
  stdout: JSON.stringify(
    Stacks: [
      Parameters: [
        {ParameterKey: 'Foo', ParameterValue: 'foo'}
        {ParameterKey: 'Bar', ParameterValue: 'bar'}
        {ParameterKey: 'Baz', ParameterValue: 'baz'}
      ]
    ]
  )
