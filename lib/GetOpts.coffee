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

  allOpts: () ->
    @config.boolean.concat(@config.string)

  allPos: () ->
    @config.positional

  configure: (opts = [], abort = true) ->
    optf = (x) -> x in opts
    @config =
      alias:      fn.selectKeys(@master.alias, opts)
      boolean:    @master.boolean.slice().filter optf
      string:     Object.keys(@master.string).filter optf
      positional: Object.keys(@master.positional).filter optf
      unknown:    if abort then @master.unknown else ((x) ->)

  usage: () ->
    bools   = @config.boolean
    strs    = @config.string
    args    = @config.positional
    alias   = (x) => if (y = @config.alias[x]) then "-#{y}, " else ''
    optbool = (x) -> "[#{alias(x)}--#{x}]"
    optstr  = (x) => "[#{alias(x)}--#{x}=#{@master.string[x]}]"
    optarg  = (x) -> if x in bools then optbool(x) else optstr(x)
    optpos  = (x) => @master.positional[x]
    bools.concat(strs).sort().map(optarg).concat(args.map(optpos).filter(fn.identity))

  parse: (argv) ->
    opts = getopts argv, @config
    args = @config.positional
    (opts[k] = arg if (k = args[i])) for arg, i in opts._
    fn.selectKeys opts, @allOpts().concat(@allPos())

  validateArgs: (opts) ->
    for k, i in @config.positional
      fn.assertOk opts[k], "#{@master.positional[k] or k} argument required"

  completeOpt: (words = []) ->
    used  = fn.objKeys(@parse words, {noenv: true}).map((x) -> "--#{x}")
    longs = @allOpts().map((x) -> "--#{x}")
    longs.sort().filter((x) -> not (x in used))

module.exports = GetOpts
