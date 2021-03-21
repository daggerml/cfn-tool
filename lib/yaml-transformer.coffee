yaml    = require 'js-yaml'
assert  = require 'assert'

typeOf = (thing) ->
  Object::toString.call(thing)[8...-1]

split = (str, sep, count=Infinity) ->
  toks  = str.split(sep)
  n     = Math.min(toks.length, count) - 1
  toks[0...n].concat(toks[n..].join(sep))

assertObject = (thing) ->
  assert.ok(typeOf(thing) in [
    'Object'
    'Undefined'
    'Null'
  ], "expected an Object, got #{JSON.stringify(thing)}")
  thing

hashMap = (args...) ->
  ret = {}
  ret[args[2*i]] = args[2*i+1] for i in [0...args.length/2]
  ret

merge = (args...) ->
  Object.assign.apply(null, args)

deepEqual = (x, y) ->
  try not assert.deepEqual(x, y) catch e then false

#=============================================================================#
# TRANSFORMER BASE CLASS                                                      #
#=============================================================================#

class YamlTransformer
  constructor: ->
    @tags     = []
    @macros   = {}
    @specials = {}
    @keystack = []
    @objstack = []

  abort: (msg...) ->
    throw new Error("at #{@keystack.join('/')}: #{msg.join(' ')}")

  walkObject: (xs) ->
    ks  = Object.keys(xs)
    @withObj xs, =>
      ks.reduce(((ret, k) =>
        v = xs[k]
        @withKey k, =>
          v = if (s = @specials[k])
            s(v)
          else if (m = @macros[k])
            m(@walk(v))
          else
            hashMap(k, @walk(v))
          if ks.length is 1 then v else merge(ret, assertObject(v))
      ), {})

  walkArray: (xs) ->
    @withObj xs, =>
      xs.map (v, i) =>
        @withKey(i, => @walk(v))

  walk: (thing) ->
    ret = switch typeOf(thing)
      when 'Object' then @walkObject(thing)
      when 'Array'  then @walkArray(thing)
      else thing
    if deepEqual(thing, ret) then ret else @walk(ret)

  withObj: (obj, f) ->
    @objstack.push(obj)
    ret = f()
    @objstack.pop()
    ret

  withKey: (key, f) ->
    @keystack.push(key?.split?(/ +/).shift())
    ret = f()
    @keystack.pop()
    ret

  deftag: (tag, long) ->
    emit = (form) -> hashMap(long, form)
    for kind in ['scalar', 'sequence', 'mapping']
      @tags.push(new yaml.Type(tag, {kind, construct: emit}))
    @

  _defform: (namespace, tag, long, emit) ->
    short = "!#{tag}"
    long ?= "Fn::#{tag}"
    @deftag(short, long)
    if emit
      namespace[long] = (args...) =>
        try
          emit.apply(null, args)
        catch e then @abort(e.message)
    @

  defspecial: (tag, long, emit) ->
    [long, emit] = [emit, long] unless emit
    @_defform(@specials, tag, long, emit)

  defmacro: (tag, long, emit) ->
    [long, emit] = [emit, long] unless emit
    @_defform(@macros, tag, long, emit)

  parse: (textOrDoc) ->
    return textOrDoc if typeOf(textOrDoc) isnt 'String'
    yaml.safeLoad(textOrDoc, {schema: yaml.Schema.create(@tags)})

  dump: (doc) ->
    yaml.safeDump(doc)

  transform: (textOrDoc) ->
    @keystack.splice(0)
    @objstack.splice(0)
    @dump(@walk(@parse(textOrDoc)))

module.exports = YamlTransformer
