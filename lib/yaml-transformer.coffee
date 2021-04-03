yaml    = require 'js-yaml'
assert  = require 'assert'
fn      = require './fn'

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
            fn.hashMap(k, @walk(v))
          if ks.length is 1 then v else fn.merge(ret, fn.assertObject(v))
      ), {})

  walkArray: (xs) ->
    @withObj xs, =>
      xs.map (v, i) =>
        @withKey("#{i}", => @walk(v))

  walk: (thing) ->
    ret = switch fn.typeOf(thing)
      when 'Object' then @walkObject(thing)
      when 'Array'  then @walkArray(thing)
      else thing
    if fn.deepEqual(thing, ret) then ret else @walk(ret)

  withObj: (obj, f) ->
    @objstack.push(obj)
    ret = f()
    @objstack.pop()
    ret

  withKey: (key, f) ->
    @keystack.push(key?.split?(/ +/).shift().replace(/^Fn::/, '!'))
    ret = f()
    @keystack.pop()
    ret

  deftag: (tag, long) ->
    emit = (form) -> fn.hashMap(long, form)
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
        catch e then @abort e
    @

  defspecial: (tag, long, emit) ->
    [long, emit] = [emit, long] unless emit
    @_defform(@specials, tag, long, emit)

  defmacro: (tag, long, emit) ->
    [long, emit] = [emit, long] unless emit
    @_defform(@macros, tag, long, emit)

  parse: (textOrDoc) ->
    return textOrDoc unless fn.isString(textOrDoc)
    yaml.safeLoad(textOrDoc, {schema: yaml.Schema.create(@tags)})

  dump: (doc) ->
    yaml.safeDump(doc)

  transform: (textOrDoc) ->
    @keystack.splice(0)
    @objstack.splice(0)
    @dump(@walk(@parse(textOrDoc)))

module.exports = YamlTransformer
