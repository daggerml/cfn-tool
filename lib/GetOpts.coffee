getopts   = require 'getopts'
path      = require 'path'
uuid      = require 'uuid'
fn        = require './fn'
CfnError  = require './CfnError'

class GetOpts
  constructor: (@master) ->
    @fixRegion()

  #
  # HELPER METHODS
  #

  allOpts: () ->
    @config.boolean.concat(@config.string).sort()

  allVars: () ->
    Object.keys(@var2opt()).sort()

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
      process.env[v] = "#{opts[o]}" if opts[o]? and (clobber or not (v in @useVars()))
    @fixRegion()

  fixRegion: () ->
    [r1, r2] = [process.env.AWS_REGION, process.env.AWS_DEFAULT_REGION]
    process.env.AWS_REGION          = r2 if (r2 and not r1) or (r1 and r2 and r1 isnt r2)
    process.env.AWS_DEFAULT_REGION  = r1 if (r1 and not r2)

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

  parse: (argv, dfl) ->
    ret = getopts argv, fn.assoc @config, 'default', Object.assign(@getVars(), dfl)
    (ret[k] = arg if (k = @config.positional[i])) for arg, i in ret._
    ret

  loadConfig: (exec, opts, file) ->
    uid   = uuid.v4()
    pat   = "^\\(#{@allVars.join('\\|')}\\)$"
    parse = (x, uid) =>
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
    @setVars parse exec """
      . '#{file}'
      echo
      echo #{uid}
      for i in $(compgen -A variable |grep '#{pat}'); do
        echo $i=$(echo -n "${!i}" |base64 -w0)
      done
    """

  validateArgs: (opts) ->
    for k, i in @config.positional
      fn.assertOk opts[k], "#{@master.positional[k] or k} argument required"

module.exports = GetOpts
