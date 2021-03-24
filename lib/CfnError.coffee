class CfnError extends Error
  constructor: (message, @body, @aborting) ->
    super message
    @name = 'CfnError'

module.exports = CfnError
