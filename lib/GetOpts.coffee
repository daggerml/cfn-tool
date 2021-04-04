fs        = require 'fs'
getopts   = require 'getopts'
{inspect} = require 'util'
path      = require 'path'
uuid      = require 'uuid'
fn        = require './fn'
log       = require './log'
CfnError  = require './CfnError'

class GetOpts
  constructor: (@master) ->
    @fixRegion()

  #
  # HELPER METHODS
  #

  allOpts: () ->
    @config.boolean.concat(@config.string).sort()

  allPos: () ->
    @config.positional.sort()

  allVars: () ->
    Object.keys(@var2opt()).sort()

  configVars: () ->
    Object.keys(fn.invertObj(fn.selectKeys(@opt2var(), @allOpts())))

  useVars: () ->
    Object.keys(@var2opt()).reduce(
      (xs, x) -> if process.env[x]? then xs.concat [x] else xs
      []
    ).sort()

  opt2var: (x) ->
    if x
      @master.opt2var(x)
    else
      @allOpts().reduce(((xs, x) => fn.assoc xs, x, @opt2var(x)), {})

  var2opt: (x) ->
    inv = fn.invertObj @opt2var()
    if x then inv[x] else inv

  config2opt: (k, v) ->
    if not (k in @config.boolean) then v else (v is 'true')

  getVars: () ->
    @allOpts().reduce(
      (xs, x) =>
        v = process.env[@opt2var(x)]
        if v? then fn.assoc(xs, x, @config2opt(x, v)) else xs
      {}
    )

  setVars: (opts, {clobber = false} = {}) ->
    for o, v of @opt2var()
      if opts[o]? and (clobber or not (v in @useVars()))
        process.env[v] = "#{opts[o]}"
    @fixRegion()

  setLogLevel: (opts) ->
    log.level = switch
      when opts.verbose then 'verbose'
      when opts.quiet   then 'error'
      else              'info'
    opts

  fixRegion: () ->
    [r1, r2] = [process.env.AWS_REGION, process.env.AWS_DEFAULT_REGION]
    process.env.AWS_REGION = r2 if (r2 and not r1) or (r1 and r2 and r1 isnt r2)
    process.env.AWS_DEFAULT_REGION  = r1 if (r1 and not r2)

  loadConfig: (opts, file) ->
    return unless (vars = @configVars())?.length
    log.verbose "using config file: '#{file}'"
    try
      uid   = uuid.v4()
      pat   = "^\\(#{@configVars().join('\\|')}\\)$"
      parse = (x) =>
        lines = x.split('\n').map((x) -> x.trim()).filter(fn.identity)
        lines = lines.slice(lines.indexOf(uid) + 2)
        lines.reduce(
          (xs, line) =>
            [k, v] = fn.split(line, '=', 2)
            k = @var2opt(k)
            v = Buffer.from(v, 'base64').toString('utf-8')
            if k then fn.assoc(xs, k, @config2opt(k, v)) else xs
          {}
        )
      @setVars opts
      @setVars parse fn.execShell """
        . '#{file}'
        echo
        echo #{uid}
        for i in $(compgen -A variable |grep '#{pat}'); do
          echo $i=$(echo -n "${!i}" |base64 -w0)
        done
      """
    catch e
      e.message = e.message.split('\n').shift()
      throw e

  getopts: (argv, dfl) ->
    opts = getopts argv, dfl
    (opts[k] = arg if (k = @config.positional[i])) for arg, i in opts._
    fn.selectKeys opts, @allOpts().concat(@allPos())

  #
  # EXTERNAL API
  #

  configure: (opts = [], abort = true) ->
    optFilter = (x) -> x in opts
    @config =
      alias: fn.selectKeys(@master.alias, opts)
      boolean: @master.boolean.slice().filter optFilter
      string: Object.keys(@master.string).filter optFilter
      positional: Object.keys(@master.positional).filter optFilter
      unknown: if abort then @master.unknown else ((x) ->)

  usage: () ->
    bools   = @config.boolean
    strs    = @config.string
    args    = @config.positional
    alias   = (x) => if (y = @config.alias[x]) then "-#{y}, " else ''
    optbool = (x) => "[#{alias(x)}--#{x}]"
    optstr  = (x) => "[#{alias(x)}--#{x}=#{@master.string[x]}]"
    optarg  = (x) => if x in bools then optbool(x) else optstr(x)
    optpos  = (x) => @master.positional[x]
    bools.concat(strs).sort().map(optarg).concat(args.map(optpos).filter(fn.identity))

  parse: (argv, {key, file, noenv} = {}) ->
    conf = () => fn.assoc @config, 'default', if noenv then {} else @getVars()
    opts = @setLogLevel @getopts argv, conf()
    if (cfg = (opts[key] or file)) and fs.existsSync(cfg)
      @loadConfig(opts, cfg)
      opts = @setLogLevel @getopts argv, conf()
    @setVars opts, {clobber: true}
    log.verbose "configuration options", {body: inspect opts, {depth: null}}
    opts

  validateArgs: (opts) ->
    for k, i in @config.positional
      fn.assertOk opts[k], "#{@master.positional[k] or k} argument required"

  completeOpt: (words = []) ->
    used  = fn.objKeys(@parse words, {noenv: true}).map((x) -> "--#{x}")
    longs = @allOpts().map((x) -> "--#{x}")
    longs.sort().filter((x) -> not (x in used))

module.exports = GetOpts
