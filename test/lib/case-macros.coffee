module.exports = (api) ->
  api.defmacro 'UpperCase', (form) -> form.toUpperCase()
  api.defmacro 'LowerCase', (form) -> form.toLowerCase()
