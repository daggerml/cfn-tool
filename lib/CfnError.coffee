class CfnError extends Error
  constructor: (message, @body, @aborting) ->
    super message

module.exports = CfnError
