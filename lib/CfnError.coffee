class CfnError extends Error
  constructor: (message, @body) ->
    super message

module.exports = CfnError
