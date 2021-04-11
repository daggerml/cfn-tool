module.exports = (api) ->
  api.defmacro 'PutState', (form) ->
    api.state()[form[0]] = form[1]
    null

  api.defmacro 'GetState', (form) ->
    api.state()[form[0]] ? form[1]
