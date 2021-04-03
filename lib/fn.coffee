assert    = require 'assert'
crypto    = require 'crypto'
fs        = require 'fs'
path      = require 'path'
CfnError  = require './CfnError'

dbg = (x) ->
  console.log require('util').inspect {dbg: x}, {depth: null}
  x

md5 = (data) ->
  crypto.createHash("md5").update(data).digest("hex")

md5File = (filePath) ->
  md5(fs.readFileSync(filePath))

md5Dir = (dirPath) ->
  origDir = process.cwd()
  try
    process.chdir(dirPath)
    add2tree = (tree, path) -> assoc(tree, path, md5Path(path))
    md5(JSON.stringify(fs.readdirSync('.').sort().reduce(add2tree, {})))
  finally
    process.chdir(origDir)

md5Path = (path) ->
  (if isDirectory(path) then md5Dir else md5File)(path)

identity = (x) -> x

assoc = (xs, k, v) ->
  xs[k] = v
  xs

conj = (xs, x) ->
  xs.push(x)
  xs

merge = (args...) ->
  Object.assign.apply(null, args)

deepMerge = (args...) ->
  dm = (x, y) ->
    if not (isObject(x) and isObject(y))
      y
    else
      ret = Object.assign({}, x)
      ret[k] = dm(x[k], v) for k, v of y
      ret
  args.reduce(((xs, x) -> dm(xs, x)), {})

hashMap = (args...) ->
  ret = {}
  ret[args[2*i]] = args[2*i+1] for i in [0...args.length/2]
  ret

objKeys = (x) -> Object.keys(x)

objVals = (x) -> objKeys(x).reduce(((ys, y) -> ys.concat([x[y]])), [])

reduceKv = (map, f) ->
  Object.keys(map).reduce(((xs, k) -> f(xs, k, map[k])), {})

selectKeys = (o, ks) ->
  Object.keys(o).reduce(((xs, x) -> if x in ks then assoc(xs, x, o[x]) else xs), {})

notEmpty = (map) ->
  Object.keys(map or {}).length > 0

invertObj = (o) ->
  Object.keys(o).reduce(((xs, x) -> assoc xs, o[x], x), {})

peek = (ary) -> ary[ary.length - 1]

getIn = (obj, ks) -> ks.reduce(((xs, x) -> xs[x]), obj)

split = (str, sep, count=Infinity) ->
  toks  = str.split(sep)
  n     = Math.min(toks.length, count) - 1
  toks[0...n].concat(toks[n..].join(sep))

assertOk = (x, msg, body) ->
  throw new CfnError(msg, body) unless x
  x

typeOf = (thing) ->
  Object::toString.call(thing).slice(8,-1)

isString  = (x) -> typeOf(x) is 'String'
isArray   = (x) -> typeOf(x) is 'Array'
isObject  = (x) -> typeOf(x) is 'Object'
isBoolean = (x) -> typeOf(x) is 'Boolean'

assertObject = (thing) ->
  assert.ok(typeOf(thing) in [
    'Object'
    'Undefined'
    'Null'
  ], "expected an Object, got #{JSON.stringify(thing)}")
  thing

assertArray = (thing) ->
  assert.ok(isArray(thing), "expected an Array, got #{JSON.stringify(thing)}")
  thing

isDirectory = (file) ->
  fs.statSync(file).isDirectory()

fileExt = (file) ->
  if (e = split(path.basename(file), '.', 2)[1])? then ".#{e}"

readFile = (file) ->
  fs.readFileSync(file).toString('utf-8')

abortOnException = (abort, lib, fn) ->
  (if typeOf(fn) is 'Array' then fn else [fn]).forEach (x) ->
    global[x] = (args...) ->
      try
        lib[x].apply(lib, args)
      catch e
        abort(e)

mergeStrings = (toks, sep = '') ->
  reducer = (xs, x) ->
    x = "#{x}" unless isObject(x)
    y = xs.pop()
    xs.concat(if isString(x) and isString(y) then [[y,x].join(sep)] else [y,x])
  toks.reduce(reducer, []).filter((x) -> x? and x isnt '')

prependLines = (x, prefix) ->
  return null unless x and isString(x)
  x.split(/\n/)
    .map((x) -> x.trimRight())
    .filter(identity)
    .map((x) -> "#{prefix}| #{x}")
    .join('\n')

rmCR = (x='') ->
  lines = []
  for v in x.split(/\r/)
    if v[0] is '\n' then v = v.slice(1) else lines.pop()
    lines.push(w) for w in v.split(/\n/)
  lines.join('\n')

deepEqual = (x, y) ->
  try not assert.deepEqual(x, y) catch e then false

module.exports = {
  # debug
  dbg

  # crypto
  md5
  md5File
  md5Dir
  md5Path

  # values
  identity
  deepEqual

  # collections
  assoc
  conj
  merge
  deepMerge
  hashMap
  objKeys
  objVals
  reduceKv
  selectKeys
  notEmpty
  invertObj
  peek
  getIn
  split

  # strings
  mergeStrings
  prependLines
  rmCR

  # decorators
  abortOnException

  # types
  typeOf
  isString
  isArray
  isObject
  isBoolean
  isDirectory

  # assertions
  assertOk
  assertObject
  assertArray

  # files
  fileExt
  readFile
}
