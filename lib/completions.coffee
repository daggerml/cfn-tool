fn = require './fn'

prefixFilter = (prefix, xs) ->
  xs.filter((x) -> x and ((not prefix) or x.startsWith(prefix))).join('\n')

exec = (cmd) ->
  try fn.execShell(cmd).trimRight() catch e

none = module.exports.none = (prefix) ->

file = module.exports.file = (prefix) ->
  exec """
    compgen -f '#{prefix}'
  """

list = module.exports.list = (prefix, words) ->
  prefixFilter prefix, words

profile = module.exports.profile = (prefix) ->
  prefixFilter prefix, exec('aws configure list-profiles').split('\n')

region = module.exports.region = (prefix) ->
  list prefix, [
    'ap-south-1'
    'eu-west-2'
    'eu-west-1'
    'ap-northeast-2'
    'ap-northeast-1'
    'sa-east-1'
    'ca-central-1'
    'ap-southeast-1'
    'ap-southeast-2'
    'eu-central-1'
    'us-east-1'
    'us-east-2'
    'us-west-1'
    'us-west-2'
  ]
