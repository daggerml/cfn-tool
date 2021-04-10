assert              = require 'assert'
sq                  = require 'shell-quote'
fn                  = require '../lib/fn'
{version: VERSION}  = require '../package.json'
{
  cfn_tool
  cfn_complete
  assertExit
  assertOpt
  assertEnv
  assertVerbose
  assertInfo
  assertError
  assertShell
  assertResult
}                   = require './util'

TPL = 'test/data/config1.yaml'
STK = 'mystack'
LNT = 'cat'

validateCmd = (tool, tpl) ->
  """
    aws cloudformation validate-template \
    --template-body \"$(cat '#{tool.opts.tmpdir}/#{fn.md5File tpl}.yaml')\"
  """

deployCmd = (tool, tpl, stack) ->
  """
    aws cloudformation deploy \
    --template-file '#{tool.opts.tmpdir}/#{fn.md5File tpl}.yaml' \
    --stack-name '#{stack}' \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_IAM CAPABILITY_AUTO_EXPAND
  """

lintCmd = (tool, tpl, cmd) ->
  "#{cmd} #{tool.opts.tmpdir}/#{fn.md5File tpl}.yaml"

testcase = (spec, cfg, f) ->
  [f, cfg]  = [cfg, f] unless f
  words     = sq.parse(spec)
  idx0      = words.indexOf('cfn-tool')
  args      = words.slice(idx0 + 1)
  vars      = words.slice(0, idx0)
  addkv     = (xs, x) -> do ([k, v] = x.split('=')) -> fn.assoc xs, k, v
  env       = vars.reduce(addkv, {})
  it spec, -> f cfn_tool args, env, cfg

describe 'cli tests', ->

  testcase "cfn-tool --help", (x) ->
    assertExit x, 0
    assertOpt x, 'help', true

  testcase "cfn-tool --version", (x) ->
    assertExit x, 0
    assertResult x, VERSION

  testcase "cfn-tool transform #{TPL}", (x) ->
    assertExit x, 0
    assertResult x, """
      us-west-2:
        foo:
          bar: 100
    """

  testcase "cfn-tool transform --region us-north-7 --profile foop #{TPL}", 'test/.cfn-config', (x) ->
    assertExit x, 0
    assertEnv x, 'AWS_PROFILE', 'foop'
    assertEnv x, 'AWS_REGION', 'us-north-7'
    assertEnv x, 'AWS_DEFAULT_REGION', 'us-north-7'
    assertResult x, """
      us-west-2:
        foo:
          bar: 100
    """

  testcase "cfn-tool transform #{TPL} --linter #{LNT}", (x) ->
    assertExit x, 0
    assertShell x, lintCmd(x, TPL, LNT)
    assertResult x, """
      us-west-2:
        foo:
          bar: 100
    """

  testcase "cfn-tool transform --keep #{TPL}", (x) ->
    assertExit x, 1
    assertError x, "unknown option: 'keep'"

  testcase "cfn-tool deploy #{TPL} #{STK}", (x) ->
    assertExit x, 0
    assertShell x, validateCmd(x, TPL)
    assertShell x, deployCmd(x, TPL, STK)
    assertInfo x, 'done -- no errors'

  testcase "cfn-tool deploy --linter #{LNT} #{TPL} #{STK}", (x) ->
    assertExit x, 0
    assertShell x, lintCmd(x, TPL, LNT)
    assertShell x, validateCmd(x, TPL)
    assertShell x, deployCmd(x, TPL, STK)
    assertInfo x, 'done -- no errors'

  testcase "cfn-tool update --parameters \"Foo=omg Bar=lol\" #{STK}", (x) ->
    assertExit x, 0
    assertShell x, """
      aws cloudformation update-stack \
      --stack-name #{STK} \
      --parameters \
      ParameterKey=Foo,ParameterValue=omg \
      ParameterKey=Bar,ParameterValue=lol \
      ParameterKey=Baz,UsePreviousValue=true \
      --capabilities \
      CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
      ----use-previous-template
    """
    assertInfo x, 'done -- no errors'
