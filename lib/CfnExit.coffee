class CfnExit extends Error
  constructor: (@status) ->
    super "exit"
    @name = 'CfnExit'

module.exports = CfnExit
