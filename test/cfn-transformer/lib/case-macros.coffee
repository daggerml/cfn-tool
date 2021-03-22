module.exports = (compiler) ->
  compiler.defmacro 'UpperCase', (form) -> form.toUpperCase()
  compiler.defmacro 'LowerCase', (form) -> form.toLowerCase()
