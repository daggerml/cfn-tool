fs                  = require 'fs'
os                  = require 'os'
path                = require 'path'
sq                  = require 'shell-quote'
GetOpts             = require './lib/GetOpts'
yaml                = require 'js-yaml'
{strict: assert}    = require 'assert'
completions         = require './lib/completions'
fn                  = require './lib/fn'
log                 = require './lib/log'
CfnError            = require './lib/CfnError'
CfnExit             = require './lib/CfnExit'
CfnTransformer      = require './lib/cfn-transformer'
{version: VERSION}  = require './package.json'

class CfnTool

  constructor: () ->
    @options = new GetOpts(
      alias:
        bucket:     'b'
        config:     'c'
        help:       'h'
        keep:       'k'
        linter:     'l'
        parameters: 'P'
        profile:    'p'
        quiet:      'q'
        region:     'r'
        tags:       't'
        verbose:    'v'
        version:    'V'
      boolean: [
        'help'
        'keep'
        'quiet'
        'verbose'
        'version'
      ]
      string:
        bucket:     '<name>'
        config:     '<file>'
        linter:     '<command>'
        parameters: '"<key>=<val> ..."'
        profile:    '<name>'
        region:     '<name>'
        tags:       '"<key>=<val> ..."'
      positional:
        command:    null
        template:   '<template-file>'
        stackname:  '<stack-name>'
      opt2var: (opt) ->
        switch opt
          when 'profile' then 'AWS_PROFILE'
          when 'region' then 'AWS_REGION'
          else "CFN_TOOL_#{opt.toUpperCase()}"
      complete:
        bucket:     completions.none
        config:     completions.none
        linter:     completions.none
        parameters: completions.none
        profile:    completions.profile
        region:     completions.region
        tags:       completions.none
        template:   completions.none
        stackname:  completions.none
      unknown: (x) => @abort new CfnError("unknown option: '#{x}'")
    )

    @defaultOptionsSpec = [
      'help'
      'version'
      'command'
    ]

    @optionsSpecs =
      deploy: [
        'bucket'
        'config'
        'help'
        'keep'
        'linter'
        'parameters'
        'profile'
        'quiet'
        'region'
        'tags'
        'verbose'
        'command'
        'template'
        'stackname'
      ]
      transform: [
        'config'
        'help'
        'linter'
        'profile'
        'quiet'
        'region'
        'tags'
        'verbose'
        'command'
        'template'
      ]
      update: [
        'config'
        'help'
        'parameters'
        'profile'
        'quiet'
        'region'
        'verbose'
        'command'
        'stackname'
      ]

    @allCmds = Object.keys(@optionsSpecs)
    @DEFAULT_CONFIG = '.cfn-tool'

  test: (f) ->
    fn.testing true
    try f() catch e
      if e.name is 'CfnExit'
        fn.testing(false) or @
      else @test => @abort(e)

  prod: (f) ->
    try f() catch e
      if e.name is 'CfnExit'
        process.exit(e.status)
      else @prod => @abort(e)

  exit: (status = 0) ->
    @exitStatus   = status
    @sideEffects  = log.sideEffects()
    throw new CfnExit(status)

  quit: (msg, status = 0) ->
    log.console msg
    @exit status

  abort: (e) ->
    e = new CfnError(e.message) if e.code is 'ENOENT'
    body = if e instanceof CfnError then e.body else e.body or e.stack
    log.error(e.message, {body})
    @exit 1

  usageCmd: (prog, cmd) ->
    @options.configure((if cmd then @optionsSpecs[cmd] else @defaultOptionsSpec), @env)
    lpad  = (x) -> "  #{x}"
    opts  = @options.usage().map(lpad).join("\n")
    "#{prog}#{if cmd then " #{cmd}" else ''}#{if opts then "\n#{opts}" else ''}"

  usage: (prog, cmd, status) ->
    manp  = [prog].concat(if cmd then [cmd] else []).join('-')
    ucmd  = fn.partial @usageCmd, @, prog
    text  = if cmd then ucmd(cmd) else [null].concat(@allCmds).map(ucmd).join("\n\n")
    @quit """
      #{text}

      See the manpage:
      * cmd: man #{manp}
      * url: http://htmlpreview.github.io/?https://github.com/daggerml/cfn-tool/blob/#{VERSION}/man/#{manp}.html
    """, status

  version: () -> @quit VERSION

  bashCompletion: (argv, @env) ->
    log.level('console')
    [$0, prefix, prev] = argv.slice(2)
    words = sq.parse(@env.COMP_LINE).slice(1)
    words.pop() if prefix
    command = words[0]
    if $0 is prev and words.length < 2
      @options.configure @defaultOptionsSpec, @env, false
      @quit completions.list prefix, @allCmds.concat(@options.completeOpt(words))
    else if (spec = @optionsSpecs[command])
      @options.configure spec, @env, false
      @opts = @options.completeOpt()
      if prev in @opts
        @quit(c(prefix)) if (c = @options.master.complete[prev.replace(/^-+/, '')])
      if prefix.startsWith('-')
        @quit completions.list prefix, @options.completeOpt(words)
      @opts = @options.parse words, {noenv: true}
      for x in @options.config.positional
        continue if @opts[x]
        @quit(c(prefix)) if (c = @options.master.complete[x])
      @quit()
    @quit completions.file prefix

  main: (argv, @env, cfg=@DEFAULT_CONFIG) ->
    if (spec = @optionsSpecs[argv[2]]) then @options.configure(spec, @env)
    else @options.configure(@defaultOptionsSpec, @env, false)

    prog          = log.PROG
    argv          = argv.slice(2)
    @opts         = @options.parse argv, {key: 'config', file: cfg}
    @opts.tmpdir  = fn.tmpdir 'cfn-tool-', @opts.keep
    cmdKnown      = (@opts.command in @allCmds) or not @opts.command

    fn.assertOk cmdKnown, "unknown command: '#{@opts.command}'"

    switch
      when @opts.help        then @usage(prog, @opts.command)
      when @opts.version     then @version()
      when not @opts.command then @usage(prog, null, 1)

    @options.validateArgs(@opts)

    switch @opts.command
      when 'transform'
        Object.assign @opts,
          dovalidate: false
          dopackage:  false
          bucket:     'example-bucket'
          s3bucket:   'example-bucket'

        log.verbose 'preparing template'
        cfn = new CfnTransformer {@opts}
        res = cfn.writeTemplate(@opts.template)

        log.console fs.readFileSync(res.tmpPath).toString('utf-8').trimRight()
      when 'deploy'
        Object.assign @opts,
          dovalidate: true
          dopackage:  true
          s3bucket:   @opts.bucket

        log.info 'preparing templates'
        cfn = new CfnTransformer {@opts}
        res = cfn.writeTemplate(@opts.template)

        if res.nested.length > 1
          throw new CfnError('bucket required for nested stacks') unless @opts.bucket
          log.info 'uploading templates to S3'
          fn.execShell "aws s3 sync --size-only '#{@opts.tmpdir}' 's3://#{@opts.bucket}/'"

        bucketarg = "--s3-bucket '#{@opts.bucket}' --s3-prefix aws/" if @opts.bucket
        paramsarg = "--parameter-overrides #{@opts.parameters}"      if @opts.parameters
        tagsarg   = "--tags #{@opts.tags}"                           if @opts.tags

        log.info 'deploying stack'
        fn.execShell """
          aws cloudformation deploy \
            --template-file '#{res.tmpPath}' \
            --stack-name '#{@opts.stackname}' \
            --capabilities CAPABILITY_NAMED_IAM CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
            #{bucketarg or ''} #{paramsarg or ''} #{tagsarg or ''}
        """

        log.info 'done -- no errors'
      when 'update'
        res = JSON.parse fn.execShell """
          aws cloudformation describe-stacks --stack-name '#{@opts.stackname}'
        """

        params = res?.Stacks?[0]?.Parameters?.reduce(
          (xs, x) ->
            k = x.ParameterKey
            fn.assoc xs, k, "ParameterKey=#{k},UsePreviousValue=true"
          {}
        )
        fn.assertOk Object.keys(params).length, "stack '#{@opts.stackname}' has no parameters"

        haveOverride = null
        for x in (@opts.parameters?.split(/ +/) or [])
          [k, v] = fn.split(x, '=', 2)
          fn.assertOk k and v, "parameter: expected <key>=<value>: got '#{x}'"
          fn.assertOk params[k], "stack '#{@opts.stackname}' has no parameter '#{k}'"
          haveOverride = params[k] = "ParameterKey=#{k},ParameterValue=#{v}"

        fn.assertOk haveOverride, 'parameter overrides required'

        paramsarg = fn.objVals(params).join(' ')

        fn.execShell """
          aws cloudformation update-stack \
            --stack-name #{@opts.stackname} \
            --parameters #{paramsarg} \
            --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
            ----use-previous-template
        """

        log.info 'done -- no errors'

    @quit()

module.exports = CfnTool
