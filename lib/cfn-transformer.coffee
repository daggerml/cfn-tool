yaml            = require 'js-yaml'
fs              = require 'fs'
os              = require 'os'
path            = require 'path'
assert          = require 'assert'
crypto          = require 'crypto'
{spawnSync}     = require 'child_process'
log             = require './log'
CfnError        = require './CfnError'
YamlTransformer = require './yaml-transformer'
{ResourceTypes} = require './schema/CloudFormationResourceSpecification.json'

#=============================================================================#
# Helper functions.                                                           #
#=============================================================================#

topLevelResourceProperties = [
  'Type'
  'Condition'
  'CreationPolicy'
  'DeletionPolicy'
  'DependsOn'
  'Metadata'
  'UpdatePolicy'
  'UpdateReplacePolicy'
]

identity = (x) -> x

assoc = (xs, k, v) ->
  xs[k] = v
  xs

conj = (xs, x) ->
  xs.push(x)
  xs

readFile = (file) ->
  fs.readFileSync(file).toString('utf-8')

typeOf = (thing) ->
  Object::toString.call(thing)[8...-1]

fileExt = (file) ->
  if (e = split(path.basename(file), '.', 2)[1])? then ".#{e}"

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

isDirectory = (file) ->
  fs.statSync(file).isDirectory()

reduceKv = (map, f) ->
  Object.keys(map).reduce(((xs, k) -> f(xs, k, map[k])), {})

notEmpty = (map) ->
  Object.keys(map or {}).length > 0

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

peek = (ary) -> ary[ary.length - 1]

getIn = (obj, ks) -> ks.reduce(((xs, x) -> xs[x]), obj)

split = (str, sep, count=Infinity) ->
  toks  = str.split(sep)
  n     = Math.min(toks.length, count) - 1
  toks[0...n].concat(toks[n..].join(sep))

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

parseKeyOpt = (opt) ->
  if (multi = opt.match(/^\[(.*)\]$/)) then multi[1].split(',') else opt

parseKeyOpts = (opts) ->
  opts.reduce(((xs, x) ->
    [k, v] = x.split('=')
    v ?= k
    merge(xs, hashMap(k, parseKeyOpt(v)))
  ), {})

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

indexOfClosingCurly = (form) ->
  depth = 0
  for i in [0...form.length]
    switch form[i]
      when '{' then depth++
      when '}' then return i if not depth--
  return -1

interpolateSub = (form) ->
  ret = []
  while true
    if form.startsWith('${!')
      ret.push(form[0...3])
      form = form[3..]
    else if form.startsWith('${')
      i = indexOfClosingCurly(form[2..])
      assert.notEqual(i, -1, "no closing curly: #{JSON.stringify(form)}")
      ret.push({Ref: form[2...i+2]})
      form = form[i+3..]
    else
      if (i = form.indexOf('${')) is -1
        ret.push(form)
        break
      else
        ret.push(form[0...i])
        form = form[i..]
  ret

#=============================================================================#
# AWS CLOUDFORMATION YAML TRANSFORMER BASE CLASS                              #
#=============================================================================#

class CfnTransformer extends YamlTransformer
  constructor: ({
    @basedir, @tmpdir, @cache, @s3bucket, @s3prefix, @verbose, @linter,
    @dolint, @dovalidate, @dopackage
  } = {}) ->
    super()

    @cache          ?= {}
    @basedir        ?= process.cwd()
    @s3prefix       ?= ''
    @tmpdir         ?= fs.mkdtempSync("#{os.tmpdir()}/")
    @template       = null
    @resourceMacros = []
    @bindstack      = []
    @nested         = []

    #=========================================================================#
    # Redefine and extend built-in CloudFormation macros.                     #
    #=========================================================================#

    @defmacro 'Base64', (form) =>
      form = if isArray(form) then form[0] else form
      {'Fn::Base64': form}

    @defmacro 'GetAZs', (form) =>
      form = if isArray(form) then form[0] else form
      {'Fn::GetAZs': form}

    @defmacro 'ImportValue', (form) =>
      form = if isArray(form) then form[0] else form
      {'Fn::ImportValue': form}

    @defmacro 'GetAtt', (form) =>
      form = if isArray(form) and form.length is 1 then form[0] else form
      {'Fn::GetAtt': if isString(form) then split(form, '.', 2) else form}

    @defmacro 'RefAll', (form) =>
      form = if isArray(form) then form[0] else form
      {'Fn::RefAll': form}

    @defmacro 'Join', (form) =>
      [sep, toks] = form
      switch (xs = mergeStrings(toks, sep)).length
        when 0 then ''
        when 1 then xs[0]
        else {'Fn::Join': [sep, xs]}

    @defmacro 'Condition', 'Condition', (form) =>
      {Condition: if isArray(form) then form[0] else form}

    @defmacro 'Ref', 'Ref', (form) =>
      form = if isArray(form) then form[0] else form
      if isString(form)
        [ref, ks...] = form.split('.')
        switch
          when form.startsWith('$')     then {'Fn::Env': form[1..]}
          when form.startsWith('%')     then {'Fn::Get': form[1..]}
          when form.startsWith('@')     then {'Fn::Attr': form[1..]}
          when peek(@bindstack)[ref]?   then getIn(peek(@bindstack)[ref], ks)
          else {Ref: form}
      else form

    @defmacro 'Sub', (form) =>
      form = if isArray(form) and form.length is 1 then form[0] else form
      switch typeOf(form)
        when 'String' then {'Fn::Join': ['', interpolateSub(form)]}
        else {'Fn::Sub': form}

    #=========================================================================#
    # Define special forms.                                                   #
    #=========================================================================#

    @defspecial 'Let', (form) =>
      form = if isArray(form) and form.length is 1 then form[0] else form
      if isArray(form)
        @withBindings(@walk(form[0]), => @walk(form[1]))
      else
        merge(peek(@bindstack), assertObject(@walk(form)))
        null

    @defspecial 'Do', (form) =>
      assertArray(form).reduce(((xs, x) => @walk(x)), null)

    #=========================================================================#
    # Define custom macros.                                                   #
    #=========================================================================#

    @defmacro 'Require', (form) =>
      form = [form] unless isArray(form)
      require(path.resolve(v))(@) for v in form
      null

    @defmacro 'Parameters', (form) =>
      Parameters: form.reduce(((xs, param) =>
        [name, opts...] = param.split(/ +/)
        opts = merge({Type: 'String'}, parseKeyOpts(opts))
        merge(xs, hashMap(name, opts))
      ), {})

    @defmacro 'Return', (form) =>
      Outputs: reduceKv form, (xs, k, v) =>
        [name, opts...] = k.split(/ +/)
        xport = if notEmpty(opts = parseKeyOpts(opts))
          opts.Name = @walk {'Fn::Sub': opts.Name} if opts.Name
          {Export: opts}
        merge(xs, hashMap(name, merge({Value: v}, xport)))

    @defmacro 'Resources', (form) =>
      ret = {}
      for id, body of form
        [id, Type, opts...] = id.split(/ +/)
        id = @walk {'Fn::Sub': id}
        ret[id] = if not Type
          if (m = @resourceMacros[body.Type]) then m(body) else body
        else
          body = merge({Type}, parseKeyOpts(opts), {Properties: body})
          if (m = @resourceMacros[Type]) then m(body) else body
      Resources: ret

    @defmacro 'Attr', (form) =>
      form = if isArray(form) then form[0] else form
      {'Fn::GetAtt': split(form, '.', 2).map((x) => {'Fn::Sub': x})}

    @defmacro 'Get', (form) =>
      form = if isArray(form) and form.length is 1 then form[0] else form
      form = form.split('.') if isString(form)
      {'Fn::FindInMap': form.map((x) => {'Fn::Sub': x})}

    @defmacro 'Env', (form) =>
      form = if isArray(form) then form[0] else form
      ret = process.env[form]
      throw new CfnError("required environment variable not set: #{form}") unless ret
      ret

    @defmacro 'Var', (form) =>
      form = if isArray(form) then form[0] else form
      {'Fn::ImportValue': {'Fn::Sub': form}}

    @defmacro 'Shell', (form) =>
      form = if isArray(form) then form[0] else form
      key  = JSON.stringify {shell: [@template, form]}
      @cache[key] = (@execShell(form) or '').replace(/\n$/, '') unless @cache[key]?
      @cache[key]

    @defmacro 'Package', (form) =>
      @packageMacro form

    @defmacro 'PackageURL', (form) =>
      {S3Bucket, S3Key} = @packageMacro form
      "https://s3.amazonaws.com/#{S3Bucket}/#{S3Key}"

    @defmacro 'PackageURI', (form) =>
      {S3Bucket, S3Key} = @packageMacro form
      "s3://#{S3Bucket}/#{S3Key}"

    @defmacro 'PackageTemplateURL', (form) =>
      {S3Bucket, S3Key} = @packageMacro form, {Parse: true}
      "https://s3.amazonaws.com/#{S3Bucket}/#{S3Key}"

    @defmacro 'YamlParse', (form) =>
      form = if isArray(form) then form[0] else form
      yaml.safeLoad(form)

    @defmacro 'YamlDump', (form) =>
      form = if isArray(form) then form[0] else form
      yaml.safeDump(form)

    @defmacro 'JsonParse', (form) =>
      form = if isArray(form) then form[0] else form
      JSON.parse(form)

    @defmacro 'JsonDump', (form) =>
      form = if isArray(form) then form[0] else form
      JSON.stringify(form)

    @defmacro 'File', (form) =>
      form = if isArray(form) then form[0] else form
      fs.readFileSync(form)

    @defmacro 'TemplateFile', (form) =>
      form = if isArray(form) then form[0] else form
      yaml.safeLoad(@transformTemplateFile(form))

    @defmacro 'Merge', (form) =>
      merge.apply(null, form)

    @defmacro 'DeepMerge', (form) =>
      deepMerge.apply(null, form)

    @defmacro 'Tags', (form) =>
      {Key: k, Value: form[k]} for k in Object.keys(form)

    @defresource 'Stack', (form) =>
      Type        = 'AWS::CloudFormation::Stack'
      Parameters  = {}
      Properties  = {Parameters}
      stackProps  = Object.keys(ResourceTypes[Type].Properties)
      for k, v of (form.Properties or {})
        (if k in stackProps then Properties else Parameters)[k] = v
      merge(form, {Type, Properties})

  packageMacro: (form, opts) ->
    form = if isArray(form) then form[0] else form
    form = {Path: form} if isString(form)
    form = Object.assign(form, opts)
    {Path, CacheKey, Parse} = form
    if @dopackage
      key  = JSON.stringify {package: [@userPath(Path), CacheKey, Parse]}
      if not @cache[key]?
        @cache[key] = (
          if isDirectory(Path)
            @writeDir(Path, CacheKey)
          else if Parse
            @writeTemplate(Path, CacheKey)
          else
            @writeFile(Path, CacheKey)
        ).code
      @cache[key]
    else
      S3Bucket: 'example-bucket'
      S3Key:    "#{@s3prefix}example-key"

  wrapError: (e) ->
    switch
      when e.name is 'CfnError' then e
      when e.name is 'Error' then new CfnError(e.message)
      else new CfnError "#{e.name}: #{e.message}"

  abort: (e) ->
    {message, body, aborting} = e = @wrapError(e)
    if not aborting
      errmsg = []
      errmsg.push(message) if message
      errmsg.push("in #{@template}") if @template
      errmsg.push("at #{@keystack.join('/')}") if @keystack.length
      e.message = errmsg.join('\n')
    e.aborting = true
    throw e

  handleShell: (cmd, res, raw) ->
    cmd = prependLines cmd, 'cmd'
    stdout = res.stdout?.toString('utf-8')
    stderr = res.stderr?.toString('utf-8')
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

  execShell: (cmd, opts, raw=false) ->
    res = spawnSync(cmd, merge({stdio: 'pipe', shell: '/bin/bash'}, opts))
    @handleShell cmd, res, raw

  execShellArgs: (cmd, args, opts, raw=false) ->
    res = spawnSync(cmd, args, merge({stdio: 'pipe', shell: '/bin/bash'}, opts))
    @handleShell cmd, res, raw

  withCwd: (dir, f) ->
    old = process.cwd()
    process.chdir(dir)
    try f() finally process.chdir(old)

  withKeyStack: (ks, f) ->
    [@keystack, old] = [ks, @keystack]
    ret = f()
    @keystack = old
    ret

  withBindings: (bindings, f) ->
    @bindstack.push(merge({}, peek(@bindstack), assertObject(bindings)))
    ret = f()
    @bindstack.pop()
    ret

  canonicalKeyPath: () -> [@template].concat(@keystack)

  canonicalHash: (fileOrDir, key) ->
    if key then md5(JSON.stringify([@canonicalKeyPath(),key])) else md5Path(fileOrDir)

  writePaths: (fileName, ext = '') ->
    throw new CfnError("can't generate S3 URL: no S3 bucket configured") unless @s3bucket
    fileName = "#{fileName}#{ext}"
    nested:   @nested
    tmpPath:  @tmpPath(fileName),
    code:     { S3Bucket: @s3bucket, S3Key: "#{@s3prefix}#{fileName}" }

  writeText: (text, ext, key, source='none') ->
    ret = @writePaths(md5(key or text), ext)
    log.verbose "wrote #{@userPath source} -> #{ret.tmpPath}"
    fs.writeFileSync(ret.tmpPath, text)
    ret

  transformTemplateFile: (file) ->
    xformer = new @.constructor({
      @basedir, @tmpdir, @cache, @s3bucket, @s3prefix, @verbose, @linter,
      @dolint, @dovalidate, @dopackage
    })
    ret = xformer.transformFile(file)
    @nested = @nested.concat xformer.nested
    ret

  tryExecRaw: (cmd, msg) ->
    res = @execShell cmd, null, true
    cmd = prependLines cmd, 'cmd'
    if res.status is 0
      log.verbose "bash: status 0", {body: "#{cmd}\n#{res.all}"}
    else
      log.verbose "bash: exit status #{res.status}", {body: cmd}
      throw new CfnError msg, res.all

  lint: (file) ->
    log.verbose "linting #{@template}"
    cmd = "#{@linter} #{file}"
    @withCwd @basedir, (() => @tryExecRaw(cmd, 'lint error'))

  validate: (file) ->
    log.verbose "validating #{@template}"
    cmd = """
      aws cloudformation validate-template \
        --template-body "$(cat '#{file}')"
    """
    @tryExecRaw cmd, 'aws cloudformation validation error'

  writeTemplate: (file, key) ->
    try
      @template = @userPath(file)
      @withKeyStack [], () =>
        ret = @writeText(@transformTemplateFile(file), fileExt(file), key, file)
        @lint ret.tmpPath if @linter and @dolint
        @validate ret.tmpPath if @dovalidate
        ret
    catch e then @abort e

  writeFile: (file, key) ->
    ret = @writePaths(@canonicalHash(file, key), fileExt(file))
    log.verbose("wrote #{@userPath file} -> #{ret.tmpPath}")
    fs.copyFileSync(file, ret.tmpPath)
    ret

  writeDir: (dir, key) ->
    tmpZip = @tmpPath("#{encodeURIComponent(@userPath(dir))}.zip")
    log.verbose("packaging: #{dir}")
    @execShell("zip -qr #{tmpZip} .", {cwd: dir})
    ret = @writePaths(@canonicalHash(dir, key), '.zip')
    log.verbose("wrote #{@userPath dir} -> #{ret.tmpPath}")
    fs.renameSync(tmpZip, ret.tmpPath)
    ret

  userPath: (file) ->
    path.relative(@basedir, file)

  tmpPath: (name) ->
    path.join(@tmpdir, name)

  pushFile: (file, f) ->
    @nested.push(@userPath file)
    [old, @template] = [@template, @userPath(file)]
    log.verbose("transforming #{@template}")
    ret = @withCwd path.dirname(file), (() -> f(path.basename(file)))
    @template = old
    ret

  pushFileCaching: (file, f) ->
    key = JSON.stringify {pushFileCaching: @userPath(file)}
    @cache[key] = @pushFile(file, f) unless @cache[key]
    @cache[key]

  defresource: (type, emit) ->
    @resourceMacros[type] = emit
    @

  transform: (text) ->
    @bindstack  = [{}]
    super(text)

  transformFile: (templateFile, doc) ->
    try
      doc = doc or fs.readFileSync(templateFile).toString('utf-8')
      @pushFileCaching templateFile, (file) => @transform(doc)
    catch e then @abort e

module.exports = CfnTransformer
