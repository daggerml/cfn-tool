yaml            = require 'js-yaml'
fs              = require 'fs'
os              = require 'os'
path            = require 'path'
assert          = require 'assert'
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
  if (multi = opt.match(/^\[(.*)\]$/)) then multi[1].split(',') else opt

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
  constructor: ({@basedir, @cache, @opts, @maps} = {}) ->
    super()

    @opts           ?= {}
    @opts.s3prefix  ?= ''
    @cache          ?= {}
    @basedir        ?= process.cwd()
    @template       = null
    @needBucket     = false
    @maps           = JSON.parse JSON.stringify(@maps or {})
    @resourceMacros = []
    @bindstack      = []
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
      form = if fn.isArray(form) then form[0] else form
      if fn.isString(form)
        [ref, ks...] = form.split('.')
        switch
          when form.startsWith('$')     then {'Fn::Env': form[1..]}
          when form.startsWith('%')     then {'Fn::Get': form[1..]}
          when form.startsWith('@')     then {'Fn::Attr': form[1..]}
          when fn.peek(@bindstack)[ref]?   then fn.getIn(@walk(fn.peek(@bindstack)[ref]), ks)
          else {Ref: form}
      else form

    @defmacro 'Sub', (form) =>
      form = if fn.isArray(form) and form.length is 1 then form[0] else form
      switch fn.typeOf(form)
        when 'Str' then {'Fn::Join': ['', interpolateSub(form)]}
        else {'Fn::Sub': form}

    #=========================================================================#
    # Define special forms.                                                   #
    #=========================================================================#

    @defspecial 'Let', (form) =>
      form = if fn.isArray(form) and form.length is 1 then form[0] else form
      if fn.isArray(form)
        @withBindings(@walk(form[0]), => @walk(form[1]))
      else
        fn.merge(fn.peek(@bindstack), fn.assertObject(@walk(form)))
        null

    @defspecial 'Do', (form) =>
      fn.assertArray(form).reduce(((xs, x) => @walk(x)), null)

    @defspecial 'Mappings', (form = {}) =>
      @maps = fn.deepMerge @maps, form
      {Mappings: @maps}

    #=========================================================================#
    # Define custom macros.                                                   #
    #=========================================================================#

    @defmacro 'Require', (form) =>
      form = [form] unless fn.isArray(form)
      require(path.resolve(v))(@) for v in form
      null

    @defmacro 'Parameters', (form) =>
      Parameters: form.reduce(((xs, param) =>
        [name, opts...] = param.split(/ +/)
        opts = fn.merge({Type: 'String'}, parseKeyOpts(opts))
        fn.merge(xs, fn.hashMap(name, opts))
      ), {})

    @defmacro 'Return', (form) =>
      @warn '!Return was deprecated in 4.2.0: use !Outputs instead'
      {'Fn::Outputs': form}

    @defmacro 'Outputs', (form) =>
      Outputs: fn.reduceKv form, (xs, k, v) =>
        [name, opts...] = k.split(/ +/)
        xport = if fn.notEmpty(opts = parseKeyOpts(opts))
          opts.Name = @walk {'Fn::Sub': opts.Name} if opts.Name
          {Export: opts}
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
        else throw new CfnError '!Shell: expected <string> or [<object>, <string>]'
      env = Object.assign({}, process.env, vars)
      @withCache {shell: [@template, form]}, () =>
        (fn.execShell(form, {env}) or '').replace(/\n$/, '')

    @defmacro 'Js', (form) =>
      [vars={}, form=''] = switch
        when fn.isArray(form) and form.length is 2  then form
        when fn.isArray(form) and form.length is 1  then [{}].concat(form)
        when fn.isString(form)                      then [{}, form]
        else throw new CfnError '!Js: expected <string> or [<object>, <string>]'
      args = Object.keys(vars)
      vals = args.reduce(((xs, x) -> xs.concat(["(#{JSON.stringify(vars[x])})"])), [])
      form = "return (function(#{args.join ','}){#{form}})(#{vals.join ','})"
      ret = @walk(new Function(form).call(@))
      throw new CfnError('!Js must not return null', form) if not ret?
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
      fs.readFileSync(form)

    @defmacro 'TemplateFile', (form) =>
      form = if fn.isArray(form) then form[0] else form
      yaml.safeLoad(@transformTemplateFile(form))

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

  macroexpand: (form) -> @walk(form)

  withCache: (key, f) ->
    key = JSON.stringify key
    (@cache[key] or (@cache[key] = [f()]))[0]

  packageMacro: (form, opts) ->
    form = if fn.isArray(form) then form[0] else form
    form = {Path: form} if fn.isString(form)
    form = Object.assign(form, opts)
    {Path, CacheKey, Parse} = form
    if @opts.dopackage
      @needBucket = true
      @withCache {package: [@userPath(Path), CacheKey, Parse]}, () =>
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

  abort: (e, {warn}) ->
    {message, body, aborting} = e = @wrapError(e)
    if not aborting
      errmsg = []
      errmsg.push(message) if message
      errmsg.push("in #{@template}") if @template
      errmsg.push("at #{@keystack.join('/')}") if @keystack.length
      e.message = errmsg.join('\n')
    e.aborting = true
    if warn then log.warn e.message else throw e

  verbose: (message, body) ->
    log.verbose message {body}

  info: (message, body) ->
    log.info message, {body}

  warn: (message, body) ->
    @abort new CfnError(message, body), {warn: true}

  withCwd: (dir, f) ->
    old = process.cwd()
    process.chdir(dir)
    try f() finally process.chdir(old)

  withKeyStack: (ks, f) ->
    [@keystack, old] = [ks, @keystack]
    ret = f()
    @keystack = old
    ret

  bindings: () ->
    Object.assign {}, @bindstack[@bindstack.length - 1]

  options: () ->
    Object.assign {}, @opts

  withBindings: (bindings, f) ->
    @bindstack.push(fn.merge({}, fn.peek(@bindstack), fn.assertObject(bindings)))
    ret = f()
    @bindstack.pop()
    ret

  canonicalKeyPath: () -> [@template].concat(@keystack)

  canonicalHash: (fileOrDir, key) ->
    if key then fn.md5(JSON.stringify([@canonicalKeyPath(),key])) else fn.md5Path(fileOrDir)

  writePaths: (fileName, ext = '') ->
    if @needBucket and not @opts.s3bucket
      throw new CfnError("can't generate S3 URL: no S3 bucket configured")
    fileName = "#{fileName}#{ext}"
    nested:   @nested
    tmpPath:  @tmpPath(fileName),
    code:     { S3Bucket: @opts.s3bucket, S3Key: "#{@opts.s3prefix}#{fileName}" }

  writeText: (text, ext, key, source='none') ->
    ret = @writePaths(fn.md5(key or text), ext)
    log.verbose "wrote '#{@userPath source}' -> '#{ret.tmpPath}'"
    fs.writeFileSync(ret.tmpPath, text)
    ret

  transformTemplateFile: (file) ->
    xformer = new @.constructor({@basedir, @cache, @opts, @maps})
    ret = xformer.transformFile(file)
    @nested = @nested.concat xformer.nested
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
    fn.tryExecRaw cmd, 'aws cloudformation validation error'

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
    path.relative(@basedir, file)

  tmpPath: (name) ->
    path.join(@opts.tmpdir, name)

  pushFile: (file, f) ->
    @nested.push(@userPath file)
    [old, @template] = [@template, @userPath(file)]
    log.verbose("transforming '#{@template}'")
    ret = @withCwd path.dirname(file), (() -> f(path.basename(file)))
    @template = old
    ret

  pushFileCaching: (file, f) ->
    @withCache {pushFileCaching: @userPath(file)}, () => @pushFile(file, f)

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
