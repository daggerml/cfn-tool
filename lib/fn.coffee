assert      = require 'assert'
{spawnSync} = require 'child_process'
crypto      = require 'crypto'
fs          = require 'fs'
os          = require 'os'
path        = require 'path'
log         = require './log'
CfnError    = require './CfnError'

#------------------------------------------------------------------------------
# debugging functions
#------------------------------------------------------------------------------

dbg = module.exports.dbg = (x) ->
  console.log require('util').inspect {dbg: x}, {depth: null}
  x

#------------------------------------------------------------------------------
# crypto functions
#------------------------------------------------------------------------------

md5 = module.exports.md5 = (data) ->
  crypto.createHash("md5").update(data).digest("hex")

md5File = module.exports.md5File = (filePath) ->
  md5(fs.readFileSync(filePath))

md5Dir = module.exports.md5Dir = (dirPath) ->
  origDir = process.cwd()
  try
    process.chdir(dirPath)
    add2tree = (tree, path) -> assoc(tree, path, md5Path(path))
    md5(JSON.stringify(fs.readdirSync('.').sort().reduce(add2tree, {})))
  finally
    process.chdir(origDir)

md5Path = module.exports.md5Path = (path) ->
  (if isDirectory(path) then md5Dir else md5File)(path)

#------------------------------------------------------------------------------
# collection functions
#------------------------------------------------------------------------------

assoc = module.exports.assoc = (xs, k, v) ->
  xs[k] = v
  xs

conj = module.exports.conj = (xs, x) ->
  xs.push(x)
  xs

merge = module.exports.merge = (args...) ->
  Object.assign.apply(null, args)

deepMerge = module.exports.deepMerge = (args...) ->
  dm = (x, y) ->
    if not (isObject(x) and isObject(y))
      y
    else
      ret = Object.assign({}, x)
      ret[k] = dm(x[k], v) for k, v of y
      ret
  args.reduce(((xs, x) -> dm(xs, x)), {})

hashMap = module.exports.hashMap = (args...) ->
  ret = {}
  ret[args[2*i]] = args[2*i+1] for i in [0...args.length/2]
  ret

objKeys = module.exports.objKeys = (x) -> Object.keys(x)

objVals = module.exports.objVals = (x) -> objKeys(x).reduce(((ys, y) -> ys.concat([x[y]])), [])

reduceKv = module.exports.reduceKv = (map, f) ->
  Object.keys(map).reduce(((xs, k) -> f(xs, k, map[k])), {})

selectKeys = module.exports.selectKeys = (o, ks) ->
  Object.keys(o).reduce(((xs, x) -> if x in ks then assoc(xs, x, o[x]) else xs), {})

notEmpty = module.exports.notEmpty = (map) ->
  Object.keys(map or {}).length > 0

invertObj = module.exports.invertObj = (o) ->
  Object.keys(o).reduce(((xs, x) -> assoc xs, o[x], x), {})

peek = module.exports.peek = (ary) -> ary[ary.length - 1]

getIn = module.exports.getIn = (obj, ks) -> ks.reduce(((xs, x) -> xs[x]), obj)

#------------------------------------------------------------------------------
# string functions
#------------------------------------------------------------------------------

split = module.exports.split = (str, sep, count=Infinity) ->
  toks  = str.split(sep)
  n     = Math.min(toks.length, count) - 1
  toks[0...n].concat(toks[n..].join(sep))

mergeStrings = module.exports.mergeStrings = (toks, sep = '') ->
  reducer = (xs, x) ->
    x = "#{x}" unless isObject(x)
    y = xs.pop()
    xs.concat(if isString(x) and isString(y) then [[y,x].join(sep)] else [y,x])
  toks.reduce(reducer, []).filter((x) -> x? and x isnt '')

prependLines = module.exports.prependLines = (x, prefix) ->
  return null unless x and isString(x)
  x.split(/\n/)
    .map((x) -> x.trimRight())
    .filter(identity)
    .map((x) -> "#{prefix}| #{x}")
    .join('\n')

rmCR = module.exports.rmCR = (x='') ->
  lines = []
  for v in x.split(/\r/)
    if v[0] is '\n' then v = v.slice(1) else lines.pop()
    lines.push(w) for w in v.split(/\n/)
  lines.join('\n')

#------------------------------------------------------------------------------
# type functions
#------------------------------------------------------------------------------

typeOf = module.exports.typeOf = (thing) ->
  Object::toString.call(thing).slice(8, 11)

isString      = module.exports.isString     = (x) -> typeOf(x) is 'Str'
isNumber      = module.exports.isNumber     = (x) -> typeOf(x) is 'Num'
isArray       = module.exports.isArray      = (x) -> typeOf(x) is 'Arr'
isObject      = module.exports.isObject     = (x) -> typeOf(x) is 'Obj'
isBoolean     = module.exports.isBoolean    = (x) -> typeOf(x) is 'Boo'
isNull        = module.exports.isNull       = (x) -> typeOf(x) is 'Nul'
isUndefined   = module.exports.isUndefined  = (x) -> typeOf(x) is 'Und'
isScalar      = module.exports.isScalar     = (x) -> typeOf(x) in ['Str', 'Num', 'Boo', 'Nul']
isCollection  = module.exports.isCollection = (x) -> typeOf(x) in ['Arr', 'Obj']

#------------------------------------------------------------------------------
# assertion functions
#------------------------------------------------------------------------------

assertOk = module.exports.assertOk = (x, msg, body) ->
  throw new CfnError(msg, body) unless x
  x

assertObject = module.exports.assertObject = (thing) ->
  assert.ok(typeOf(thing) in [
    'Obj'
    'Nul'
  ], "expected an Object, got #{JSON.stringify(thing)}")
  thing

assertArray = module.exports.assertArray = (thing) ->
  assert.ok(isArray(thing), "expected an Array, got #{JSON.stringify(thing)}")
  thing

#------------------------------------------------------------------------------
# filesystem I/O functions
#------------------------------------------------------------------------------

tmpdir = module.exports.tmpdir = (prefix, keep = false) ->
  dir = fs.mkdtempSync([os.tmpdir(), prefix].join('/'))
  process.on 'exit', () -> fs.rmdirSync(dir, {recursive: true}) unless keep
  dir

isDirectory = module.exports.isDirectory = (file) ->
  fs.statSync(file).isDirectory()

fileExt = module.exports.fileExt = (file) ->
  if (e = split(path.basename(file), '.', 2)[1])? then ".#{e}"

readFile = module.exports.readFile = (file) ->
  fs.readFileSync(file).toString('utf-8')

abortOnException = module.exports.abortOnException = (abort, lib, fn) ->
  (if typeOf(fn) is 'Array' then fn else [fn]).forEach (x) ->
    global[x] = (args...) ->
      try
        lib[x].apply(lib, args)
      catch e
        abort(e)

#------------------------------------------------------------------------------
# child process functions
#------------------------------------------------------------------------------

handleShell = module.exports.handleShell = (cmd, res, raw) ->
  cmd = prependLines cmd, 'cmd'
  stdout = rmCR res.stdout?.toString('utf-8')
  stderr = rmCR res.stderr?.toString('utf-8')
  res.out = prependLines(stdout, 'out')
  res.err = prependLines(stderr, 'err')
  res.all = [res.out, res.err].filter(identity).join('\n')
  if raw
    res
  else
    if res.status is 0
      log.verbose "bash: status 0", {body: "#{cmd}\n#{res.all}"}
      stdout
    else
      throw new CfnError("bash: exit status #{res.status}", "#{cmd}\n#{res.all}")

execShell = module.exports.execShell = (cmd, opts, raw=false) ->
  res = spawnSync(cmd, merge({stdio: 'pipe', shell: '/bin/bash'}, opts))
  handleShell cmd, res, raw

execShellArgs = module.exports.execShellArgs = (cmd, args, opts, raw=false) ->
  res = spawnSync(cmd, args, merge({stdio: 'pipe', shell: '/bin/bash'}, opts))
  handleShell cmd, res, raw

tryExecRaw = module.exports.tryExecRaw = (cmd, msg) ->
  res = execShell cmd, null, true
  cmd = prependLines cmd, 'cmd'
  if res.status is 0
    log.verbose "bash: status 0", {body: "#{cmd}\n#{res.all}"}
  else
    log.verbose "bash: exit status #{res.status}", {body: cmd}
    throw new CfnError msg, res.all

#------------------------------------------------------------------------------
# misc functions
#------------------------------------------------------------------------------

identity = module.exports.identity = (x) -> x

partial = module.exports.partial = (f, obj, args...) ->
  (args2...) -> f.apply obj, args.concat(args2)

deepEqual = module.exports.deepEqual = (x, y) ->
  try not assert.deepEqual(x, y) catch e then false
