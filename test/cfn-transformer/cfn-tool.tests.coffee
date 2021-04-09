assert              = require 'assert'
fs                  = require 'fs'
os                  = require 'os'
path                = require 'path'
fn                  = require '../../lib/fn'
log                 = require '../../lib/log'
CfnTool             = require '../../'
{version: VERSION}  = require '../../package.json'

cfn_tool = (args=[], env=[], cfg) ->
  tool = new CfnTool()
  tool.DEFAULT_CONFIG = cfg
  tool: tool.test(-> tool.main([null, null].concat(args), env))
  tmpd: tool.opts?.tmpdir
  logs: tool.sideEffects.map((x) -> x.message)
  opts: tool.opts
  exit: tool.exitStatus

validateCmd = (tmpd, tpl) ->
  """
    aws cloudformation validate-template \
    --template-body \"$(cat '#{tmpd}/#{fn.md5File tpl}.yaml')\"
  """

deployCmd = (tmpd, tpl, stack) ->
  """
    aws cloudformation deploy \
    --template-file '#{tmpd}/#{fn.md5File tpl}.yaml' \
    --stack-name '#{stack}' \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_IAM CAPABILITY_AUTO_EXPAND   
  """

lintCmd = (tmpd, tpl, cmd) ->
  "#{cmd} #{tmpd}/#{fn.md5File tpl}.yaml"

dbg = (logs) ->
  console.dir logs.reduce(((xs, x, i) -> fn.assoc xs, i, x), {})

describe 'cfn-tool', ->

  it 'cfn-tool --help', ->
    args  = ['--help']
    {tool, opts, exit, tmpd, logs} = cfn_tool(args)
    assert.equal(0,                                    exit)
    assert.equal(true,                            opts.help)

  it 'cfn-tool --version', ->
    args  = ['--version']
    {tool, opts, exit, tmpd, logs} = cfn_tool(args)
    assert.equal(0,                                    exit)
    assert.equal(true,                         opts.version)
    assert.equal(VERSION,                           logs[1])

  it 'cfn-tool transform <template-file>', ->
    cmd   = 'transform'
    file  = 'test/cfn-transformer/data/config1.yaml'
    args  = [cmd, file]
    yaml  = """
      us-west-2:
        foo:
          bar: 100
    """
    {tool, exit, tmpd, logs} = cfn_tool(args)
    assert.equal(0,                                    exit)
    assert.equal(yaml,                              logs[4])

  it 'cfn-tool transform --keep <template-file>', ->
    cmd   = 'transform'
    file  = 'test/cfn-transformer/data/config1.yaml'
    args  = [cmd, '--keep', file]
    {tool, exit, tmpd, logs} = cfn_tool(args)
    assert.equal(1,                                    exit)
    assert.equal("unknown option: 'keep'",          logs[0])

  it 'cfn-tool transform --linter <command> <template-file>', ->
    cmd   = 'transform'
    file  = 'test/cfn-transformer/data/config1.yaml'
    lint  = 'cat'
    args  = [cmd, '--linter', lint, file]
    {tool, exit, tmpd, logs} = cfn_tool(args)
    yaml  = """
      us-west-2:
        foo:
          bar: 100
    """
    assert.equal(0,                                    exit)
    assert.equal(lintCmd(tmpd, file, lint),         logs[5])
    assert.equal(yaml,                              logs[7])

  it 'cfn-tool deploy <template-file> <stack-name>', ->
    cmd   = 'deploy'
    file  = 'test/cfn-transformer/data/config1.yaml'
    stack = 'mystack'
    args  = [cmd, file, stack]
    {tool, opts, exit, tmpd, logs} = cfn_tool(args)
    assert.equal(0,                                     exit)
    assert.equal(validateCmd(tmpd, file),           logs[ 5])
    assert.equal(deployCmd(tmpd, file, stack),      logs[ 8])
    assert.equal('done -- no errors',               logs[10])

  it 'cfn-tool deploy --linter <command> <template-file> <stack-name>', ->
    cmd   = 'deploy'
    file  = 'test/cfn-transformer/data/config1.yaml'
    lint  = 'cat'
    stack = 'mystack'
    args  = [cmd, '--linter', lint, file, stack]
    {tool, opts, exit, tmpd, logs} = cfn_tool(args)
    assert.equal(0,                                     exit)
    assert.equal(lintCmd(tmpd, file, lint),         logs[ 5])
    assert.equal(validateCmd(tmpd, file),           logs[ 8])
    assert.equal(deployCmd(tmpd, file, stack),      logs[11])
    assert.equal('done -- no errors',               logs[13])

  it 'cfn-tool update --parameters "<key>=<value> ..." <stack-name>', ->
    cmd   = 'update'
    stack = 'mystack'
    param = 'Foo=omg Bar=lol'
    args  = [cmd, '--parameters', param, stack]
    fn.mockSpawn (cmd) ->
      if cmd is "aws cloudformation describe-stacks --stack-name '#{stack}'"
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
    upd8  = """
      aws cloudformation update-stack \
      --stack-name #{stack} \
      --parameters \
      ParameterKey=Foo,ParameterValue=omg \
      ParameterKey=Bar,ParameterValue=lol \
      ParameterKey=Baz,UsePreviousValue=true \
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
      ----use-previous-template
    """
    {tool, opts, exit, tmpd, logs} = cfn_tool(args)
    assert.equal(0,                                    exit)
    assert.equal(upd8,                              logs[3])
    assert.equal('done -- no errors',               logs[5])
