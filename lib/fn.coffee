CfnError = require './CfnError'

identity = (x) -> x

assoc = (xs, k, v) ->
  xs[k] = v
  xs

objKeys = (x) -> Object.keys(x)
objVals = (x) -> objKeys(x).reduce(((ys, y) -> ys.concat([x[y]])), [])

selectKeys = (o, ks) ->
  Object.keys(o).reduce(((xs, x) -> if x in ks then assoc(xs, x, o[x]) else xs), {})

invertObj = (o) ->
  Object.keys(o).reduce(((xs, x) -> assoc xs, o[x], x), {})

split = (str, sep, count=Infinity) ->
  toks  = str.split(sep)
  n     = Math.min(toks.length, count) - 1
  toks[0...n].concat(toks[n..].join(sep))

assertOk = (x, msg, body) ->
  throw new CfnError(msg, body) unless x
  x

typeOf = (thing) ->
  Object::toString.call(thing).slice(8,-1)

abortOnException = (abort, lib, fn) ->
  (if typeOf(fn) is 'Array' then fn else [fn]).forEach (x) ->
    global[x] = (args...) ->
      try
        lib[x].apply(lib, args)
      catch e
        abort(e)

module.exports = {
  identity
  assoc
  objKeys
  objVals
  selectKeys
  invertObj
  split
  assertOk
  typeOf
  abortOnException
}
