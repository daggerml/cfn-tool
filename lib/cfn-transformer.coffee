yaml            = require 'js-yaml'
fs              = require 'fs'
os              = require 'os'
path            = require 'path'
assert          = require 'assert'
uuid            = require 'uuid'
fn              = require './fn'
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

parseKeyOpt = (opt) ->
  ret = if (multi = opt.match(/^\[(.*)\]$/)) then multi[1].split(',') else opt
  if fn.isArray(ret) then ret.map((x) -> {'Fn::Sub': x}) else {'Fn::Sub': ret}

parseKeyOpts = (opts) ->
  opts.reduce(((xs, x) ->
    [k, v] = x.split('=')
    v ?= k
    fn.merge(xs, fn.hashMap(k, parseKeyOpt(v)))
  ), {})

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
      ret.push(form[0...2])
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

clone = (jsonable) -> JSON.parse JSON.stringify jsonable

#=============================================================================#
# TRANSFORMER CLASS FOR USE IN REQUIRED MACRO MODULES                         #
#=============================================================================#

class CfnModule
  constructor: (@transformer, @id) ->
    @transformer.state[@id] ?= {} if @id

  bindings: ->
    clone fn.peek @transformer.bindstack

  options: ->
    clone @transformer.opts

  state: ->
    fn.assertOk @id, 'defmacro: only allowed in !Require modules'
    @transformer.state[@id]

  defmacro: (name, args...) ->
    args[args.length - 1] = args[args.length - 1].bind(@)
    @transformer.defmacro.apply @transformer, [name].concat(args)

  defresource: (name, long, f) ->
    args[args.length - 1] = args[args.length - 1].bind(@)
    @transformer.defresource.apply @transformer, [name].concat(args)

  macroexpand: (form) ->
    @transformer.walk(form)

  md5: (text) ->
    fn.md5(text)

  tmpPath: (name) ->
    @transformer.tmpPath name

  userPath: (path) ->
    @transformer.userPath path

  error: (message, body) ->
    @transformer.abort new CfnError(message, body)

  warn: (message, body) ->
    log.warn @transformer.atLocation(message), {body}

  info: (message, body) ->
    log.info message, {body}

  verbose: (message, body) ->
    log.verbose message, {body}

  withBindings: (bindings, f) ->
    @transformer.withBindings bindings, f

  withCache: (key, f) ->
    fn.assertOk @id, 'withCache: only allowed in !Require modules'
    @transformer.withCache {module: @id, key}, f

  withCwd: (dir, f) ->
    @transformer.withCwd dir, f

#=============================================================================#
# AWS CLOUDFORMATION YAML TRANSFORMER BASE CLASS                              #
#=============================================================================#

class CfnTransformer extends YamlTransformer
  constructor: ({@ns, @basedir, @cache, @opts, @maps, @globals, @state} = {}) ->
    super()

    @ns             ?= uuid.v4()
    @opts           ?= {}
    @opts.s3prefix  ?= ''
    @cache          ?= {}
    @basedir        ?= process.cwd()
    @template       = null
    @maps           = clone(@maps or {})
    @globals        = clone(@globals or {})
    @state          = clone(@state or {})
    @resourceMacros = []
    @bindstack      = [@globals]
    @nested         = []

    #=========================================================================#
    # Redefine and extend built-in CloudFormation macros.                     #
    #=========================================================================#

    @defmacro 'Base64', (form) =>
      form = if fn.isArray(form) then form[0] else form
      {'Fn::Base64': form}

    @defmacro 'GetAZs', (form) =>
      form = if fn.isArray(form) then form[0] else form
      {'Fn::GetAZs': form}

    @defmacro 'ImportValue', (form) =>
      form = if fn.isArray(form) then form[0] else form
      {'Fn::ImportValue': form}

    @defmacro 'GetAtt', (form) =>
      form = if fn.isArray(form) and form.length is 1 then form[0] else form
      {'Fn::GetAtt': if fn.isString(form) then fn.split(form, '.', 2) else form}

    @defmacro 'RefAll', (form) =>
      form = if fn.isArray(form) then form[0] else form
      {'Fn::RefAll': form}

    @defmacro 'Join', (form) =>
      [sep, toks] = form
      switch (xs = fn.mergeStrings(toks, sep)).length
        when 0 then ''
        when 1 then xs[0]
        else {'Fn::Join': [sep, xs]}

    @defmacro 'Condition', 'Condition', (form) =>
      {Condition: if fn.isArray(form) then form[0] else form}

    @defmacro 'Ref', 'Ref', (form) =>
      dfl     = form[1] if fn.isArray(form)
      form    = fn.assertString(if fn.isArray(form) then form[0] else form)
      segs    = [ref, ks...] = form.split('.')
      bind    = fn.peek(@bindstack)
      refable = (bind[ref]? or segs.length > 1)
      getin   = (m, ks) =>
        ret = ks.reduce(((xs, x) => @walk(xs?[x])), m)
        fn.assertOk ret? or dfl?, "can't resolve: '#{ks.join('.')}'"
        ret ? dfl
      switch
        when form.startsWith('$') then {'Fn::Env': form[1..]}
        when form.startsWith('%') then {'Fn::Get': form[1..]}
        when form.startsWith('@') then {'Fn::Attr': form[1..]}
        when form.startsWith('*') then {'Fn::Var': form[1..]}
        when refable              then getin(bind, segs)
        else {Ref: form}

    @defmacro 'Sub', (form) =>
      form = switch
        when fn.isString(form)                      then [form, {}]
        when fn.isArray(form) and form.length is 1  then form.concat [{}]
        when fn.isArray(form) and form.length is 2  then form
        else throw new CfnError "invalid type: #{JSON.stringify form}"
      {'Fn::Let': [form[1], {'Fn::Join': ['', interpolateSub(form[0])]}]}

    #=========================================================================#
    # Define special forms.                                                   #
    #=========================================================================#

    @defspecial 'Let', (form) =>
      form = if fn.isArray(form) and form.length is 1 then form[0] else form
      if fn.isArray(form)
        @withBindings(@walk(form[0]), => @walk(form[1]))
      else
        fn.merge(fn.peek(@bindstack), fn.assertObject(form))
        null

    @defspecial 'Globals', (form) =>
      @globals = fn.deepMerge @globals, fn.assertObject(form)
      @bindstack.push(fn.deepMerge(@bindstack.pop(), form))
      null

    @defspecial 'Mappings', (form = {}) =>
      @maps = fn.deepMerge @maps, form
      {Mappings: @maps}

    @defspecial 'Do', (form) =>
      fn.assertArray(form).reduce(((xs, x) => @walk(x)), null)

    #=========================================================================#
    # Define custom macros.                                                   #
    #=========================================================================#

    @defmacro 'Require', (form) =>
      for v in (if fn.isArray(form) then form else [form])
        v = path.resolve(v)
        require(v)(new CfnModule(@, v))
      null

    @defmacro 'Parameters', (form) =>
      Parameters: form.reduce(((xs, param) =>
        [name, opts...] = param.split(/ +/)
        opts = fn.merge({Type: 'String'}, parseKeyOpts(opts))
        fn.merge(xs, fn.hashMap(name, opts))
      ), {})

    @defmacro 'Return', (form) =>
      log.warn @atLocation '!Return was deprecated in 4.2.0: use !Outputs instead'
      {'Fn::Outputs': form}

    @defmacro 'Outputs', (form) =>
      Outputs: fn.reduceKv form, (xs, k, v) =>
        [name, opts...] = k.split(/ +/)
        xport = if fn.notEmpty(opts = parseKeyOpts(opts)) then {Export: opts}
        fn.merge(xs, fn.hashMap(name, fn.merge({Value: v}, xport)))

    @defmacro 'Resources', (form) =>
      ret = {}
      for id, body of form
        [id, Type, opts...] = id.split(/ +/)
        id = @walk {'Fn::Sub': id}
        ret[id] = if not Type
          if (m = @resourceMacros[body.Type]) then m(body) else body
        else
          body = fn.merge({Type}, parseKeyOpts(opts), {Properties: body})
          if (m = @resourceMacros[Type]) then m(body) else body
      Resources: ret

    @defmacro 'Attr', (form) =>
      form = if fn.isArray(form) then form[0] else form
      {'Fn::GetAtt': fn.split(form, '.', 2).map((x) => {'Fn::Sub': x})}

    @defmacro 'Get', (form) =>
      form = if fn.isArray(form) and form.length is 1 then form[0] else form
      form = form.split('.') if fn.isString(form)
      {'Fn::FindInMap': form.map((x) => {'Fn::Sub': x})}

    @defmacro 'Env', (form) =>
      form = if fn.isArray(form) then form[0] else form
      ret = process.env[form]
      throw new CfnError("required environment variable not set: #{form}") unless ret
      ret

    @defmacro 'Var', (form) =>
      form = if fn.isArray(form) then form[0] else form
      {'Fn::ImportValue': {'Fn::Sub': form}}

    @defmacro 'Shell', (form) =>
      [vars={}, form=''] = switch
        when fn.isArray(form) and form.length is 2  then form
        when fn.isArray(form) and form.length is 1  then [null].concat(form)
        when fn.isString(form)                      then [null, form]
        else throw new CfnError 'expected <string> or [<object>, <string>]'
      env = Object.assign({}, process.env, vars)
      @withCache {shell: [@ns, @template, vars, form]}, () =>
        (fn.execShell(form, {env}) or '').replace(/\n$/, '')

    @defmacro 'Js', (form) =>
      [vars={}, form=''] = switch
        when fn.isArray(form) and form.length is 2  then form
        when fn.isArray(form) and form.length is 1  then [{}].concat(form)
        when fn.isString(form)                      then [{}, form]
        else throw new CfnError 'expected <string> or [<object>, <string>]'
      @withCache {js: [@ns, @template, vars, form]}, () =>
        args = Object.keys(vars)
        vals = args.reduce(((xs, x) -> xs.concat(["(#{JSON.stringify(vars[x])})"])), [])
        form = """
          return (function(#{args.join ', '}) {
            #{form}
          }).bind(arguments[0]).call(null, #{vals.join ', '})
        """
        ret = @walk (new Function(form)).call(null, new CfnModule(@))
        throw new CfnError('expected non-null result', form) unless ret?
        ret

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
      form = if fn.isArray(form) then form[0] else form
      yaml.safeLoad(form)

    @defmacro 'YamlDump', (form) =>
      form = if fn.isArray(form) then form[0] else form
      yaml.safeDump(form)

    @defmacro 'JsonParse', (form) =>
      form = if fn.isArray(form) then form[0] else form
      JSON.parse(form)

    @defmacro 'JsonDump', (form) =>
      form = if fn.isArray(form) then form[0] else form
      JSON.stringify(form)

    @defmacro 'File', (form) =>
      form = if fn.isArray(form) then form[0] else form
      @withCache {file: [@ns, path.resolve form]}, () =>
        fs.readFileSync(form).toString('utf-8')

    @defmacro 'TemplateFile', (form) =>
      form = if fn.isArray(form) then form[0] else form
      @withCache {templateFile: [@ns, path.resolve form]}, () =>
        yaml.safeLoad(@transformTemplateFile(form, true))

    @defmacro 'Md5', (form) =>
      form = if fn.isArray(form) then form[0] else form
      fn.md5(form)

    @defmacro 'Md5File', (form) =>
      form = if fn.isArray(form) then form[0] else form
      fn.md5Path(form)

    @defmacro 'Merge', (form) =>
      fn.merge.apply(null, form)

    @defmacro 'DeepMerge', (form) =>
      fn.deepMerge.apply(null, form)

    @defmacro 'Tags', (form) =>
      {Key: k, Value: form[k]} for k in Object.keys(form)

    @defresource 'Stack', (form) =>
      Type        = 'AWS::CloudFormation::Stack'
      Parameters  = {}
      Properties  = {Parameters}
      stackProps  = Object.keys(ResourceTypes[Type].Properties)
      for k, v of (form.Properties or {})
        (if k in stackProps then Properties else Parameters)[k] = v
      fn.merge(form, {Type, Properties})

  withCache: (key, f) ->
    key = JSON.stringify key
    (@cache[key] or (@cache[key] = [f()]))[0]

  addNested: (x) ->
    x = [x] if fn.isString(x)
    @nested = x.reduce(
      (xs, x) -> if x in xs then xs else xs.concat [x]
      @nested
    )

  packageMacro: (form, opts) ->
    form = if fn.isArray(form) then form[0] else form
    form = {Path: form} if fn.isString(form)
    form = Object.assign(form, opts)
    {Path, CacheKey, Parse} = form
    if @opts.dopackage
      @addNested @userPath Path
      @withCache {package: [@ns, @userPath(Path), CacheKey, Parse]}, () =>
        (
          switch
            when fn.isDirectory(Path) then @writeDir(Path, CacheKey)
            when Parse then @writeTemplate(Path, CacheKey)
            else @writeFile(Path, CacheKey)
        ).code
    else
      S3Bucket: 'example-bucket'
      S3Key:    "#{@opts.s3prefix}example-key"

  wrapError: (e) ->
    switch
      when e.name is 'CfnError' then e
      when e.name is 'Error' then new CfnError(e.message)
      else new CfnError "#{e.name}: #{e.message}"

  atLocation: (message) ->
    msg = []
    msg.push(message) if message
    msg.push("in #{@template}") if @template
    msg.push("at #{@keystack.join('/')}") if @keystack.length
    msg.join('\n')

  abort: (e) ->
    e = @wrapError(e)
    e.message = @atLocation e.message unless e.aborting
    e.aborting = true
    throw e

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
    @bindstack.push(fn.merge({}, fn.peek(@bindstack), fn.assertObject(bindings)))
    ret = f()
    @bindstack.pop()
    ret

  canonicalKeyPath: () -> [@template].concat(@keystack)

  canonicalHash: (fileOrDir, key) ->
    if key then fn.md5(JSON.stringify([@canonicalKeyPath(),key])) else fn.md5Path(fileOrDir)

  writePaths: (fileName, ext = '') ->
    fileName = "#{fileName}#{ext}"
    nested:   @nested
    tmpPath:  @tmpPath(fileName),
    code:     { S3Bucket: @opts.s3bucket, S3Key: "#{@opts.s3prefix}#{fileName}" }

  writeText: (text, ext, key, source='none') ->
    ret = @writePaths(fn.md5(key or text), ext)
    log.verbose "wrote '#{@userPath source}' -> '#{ret.tmpPath}'"
    fs.writeFileSync(ret.tmpPath, text)
    ret

  transformTemplateFile: (file, ignoreNested) ->
    xformer = new @.constructor({@ns, @basedir, @cache, @opts, @maps, @globals, @state})
    ret = xformer.transformFile(file)
    @addNested xformer.nested unless ignoreNested
    ret

  lint: (file) ->
    log.verbose "linting '#{@template}'"
    cmd = "#{@opts.linter} #{file}"
    @withCwd @basedir, (() => fn.tryExecRaw(cmd, 'lint error'))

  validate: (file) ->
    log.verbose "validating '#{@template}'"
    cmd = """
      aws cloudformation validate-template \
        --template-body "$(cat '#{file}')"
    """
    try
      fn.tryExecRaw cmd, 'aws cloudformation validation error'
    catch e
      if @opts.continue
        body = if e instanceof CfnError then e.body else e.body or e.stack
        log.error(e.message, {body})
      else throw e

  writeTemplate: (file, key) ->
    try
      @template = @userPath(file)
      @withKeyStack [], () =>
        ret = @writeText(@transformTemplateFile(file), fn.fileExt(file), key, file)
        @lint ret.tmpPath if @opts.linter
        @validate ret.tmpPath if @opts.dovalidate
        ret
    catch e then @abort e

  writeFile: (file, key) ->
    ret = @writePaths(@canonicalHash(file, key), fn.fileExt(file))
    log.verbose("wrote '#{@userPath file}' -> '#{ret.tmpPath}'")
    fs.copyFileSync(file, ret.tmpPath)
    ret

  writeDir: (dir, key) ->
    tmpZip = @tmpPath("#{encodeURIComponent(@userPath(dir))}.zip")
    log.verbose("packaging: '#{dir}'")
    fn.execShell("zip -qr #{tmpZip} .", {cwd: dir})
    ret = @writePaths(@canonicalHash(dir, key), '.zip')
    log.verbose("wrote '#{@userPath dir}' -> '#{ret.tmpPath}'")
    fs.renameSync(tmpZip, ret.tmpPath)
    ret

  userPath: (file) ->
    ret = path.relative(@basedir, file)
    if ret.startsWith('../') then path.resolve(ret) else ret

  tmpPath: (name) ->
    path.join(@opts.tmpdir, name)

  pushFile: (file, f) ->
    @addNested @userPath file
    [old, @template] = [@template, @userPath(file)]
    log.verbose("transforming '#{@template}'")
    ret = @withCwd path.dirname(file), (() -> f(path.basename(file)))
    @template = old
    ret

  pushFileCaching: (file, f) ->
    @withCache {pushFileCaching: [@ns, @userPath(file)]}, () => @pushFile(file, f)

  defresource: (type, emit) ->
    @resourceMacros[type] = emit
    @

  transform: (text, @bindstack = [{}]) ->
    super(text)

  transformFile: (templateFile, doc) ->
    try
      doc = doc or fs.readFileSync(templateFile).toString('utf-8')
      @pushFileCaching templateFile, (file) =>
        @transform doc, [{
          CfnTool: {
            BaseDir:      @basedir
            TemplateFile: templateFile
          }
        }]
    catch e then @abort e

module.exports = CfnTransformer
