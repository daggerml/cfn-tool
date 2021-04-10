assert              = require 'assert'
{inverse, dim}      = require 'chalk'
sq                  = require 'shell-quote'
fn                  = require '../lib/fn'
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

testcase = (spec, expected) ->
  point = spec.indexOf('░')
  line  = spec.split('░').join('')
  left  = line.slice(0, point)
  right = line.slice(point)
  desc  = left + inverse.dim(right[0] or ' ') + right.slice(1)
  words = sq.parse(left)
  len   = words.length
  $0    = words[0]
  pfx   = if len > 1 and not / $/.test(left) then words.pop() else ''
  prev  = words.pop()
  args  = [$0, pfx, prev]
  env   = {COMP_LINE: line, COMP_POINT: point}
  it desc, ->
    tool = cfn_complete(args, env)
    assertExit tool, 0
    assertResult tool, expected

describe 'completion tests', ->

  testcase 'cfn-tool ░', """
    deploy
    transform
    update
    --help
    --version
  """

  testcase 'cfn-tool -░', """
    --help
    --version
  """

  testcase 'cfn-tool --v░', """
    --version
  """

  testcase 'cfn-tool t░', """
    transform
  """

  testcase 'cfn-tool transform ░'

  testcase 'cfn-tool deploy --░', """
    --bucket
    --help
    --keep
    --linter
    --parameters
    --profile
    --quiet
    --region
    --tags
    --verbose
  """

  testcase 'cfn-tool deploy --bucket mybucket --░ foo.yml mystack', """
    --help
    --keep
    --linter
    --parameters
    --profile
    --quiet
    --region
    --tags
    --verbose
  """

  testcase 'cfn-tool transform --░', """
    --help
    --linter
    --profile
    --quiet
    --region
    --verbose
  """

  testcase 'cfn-tool update --░', """
    --help
    --parameters
    --profile
    --quiet
    --region
    --verbose
  """

  testcase 'cfn-tool transform foo░'

  testcase 'cfn-tool transform foop.yml --░', """
    --help
    --linter
    --profile
    --quiet
    --region
    --verbose
  """

  testcase 'cfn-tool transform foop.yml --l░', """
    --linter
  """

  testcase 'cfn-tool transform foop.yml --linter ░'

  testcase 'cfn-tool transform foop.yml --r░', """
    --region
  """

  testcase 'cfn-tool transform foop.yml --region ░', """
    ap-south-1
    eu-west-2
    eu-west-1
    ap-northeast-2
    ap-northeast-1
    sa-east-1
    ca-central-1
    ap-southeast-1
    ap-southeast-2
    eu-central-1
    us-east-1
    us-east-2
    us-west-1
    us-west-2
  """

  testcase 'cfn-tool transform foop.yml --p░', """
    --profile
  """

  testcase 'cfn-tool transform foop.yml --profile ░', """
    default
    foop
    barp
  """

  testcase 'cfn-tool transform foop.yml --░profile ', """
    --help
    --linter
    --profile
    --quiet
    --region
    --verbose
  """

  testcase 'cfn-tool transform foop.░yml --profile '
