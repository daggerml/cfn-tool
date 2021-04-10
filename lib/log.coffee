{ createLogger }  = winston = require 'winston'
{ stderr }        = require 'chalk'
{ MESSAGE }       = require 'triple-beam'
{ basename }      = require 'path'

levels =
  console:  0
  error:    0
  warn:     1
  info:     2
  verbose:  3
  spawn:    4

class Logger
  constructor: ->
    format = (
      winston.format (info, opts) =>
        colors =
          error:    stderr.red
          warn:     stderr.yellow
          info:     stderr
          verbose:  stderr

        if not (info.level in ['console', 'spawn'])
          color         = colors[info.level]
          verbose       = levels[@logger.level] > levels.info or
                          levels[info.level] < levels.info
          lines         = info.message.split('\n').map((x) -> x.trimRight()).filter((x) -> x)
          message1      = color.bold("#{@PROG}: #{lines.shift()}")
          message2      = color(lines.join('\n')) if lines.length
          body          = stderr.dim(info.body) if info.body and verbose
          info[MESSAGE] = [message1, message2, body].filter((x) -> x).join('\n')
        else
          info[MESSAGE] = info.message

        @SIDE_EFFECTS?.push(info)
        info
    )()

    transports = [
      new winston.transports.Console(
        stderrLevels: [
          'error'
          'warn'
          'info'
          'verbose'
        ]
      )
    ]

    @PROG         = basename(process.argv[1] or 'repl')
    @SIDE_EFFECTS = null
    @logger       = createLogger { levels, format, transports }

  level: (x) ->
    @logger.level = x unless @logger.level is 'console'

  silence: (enable) ->
    (x.silent = !!enable) for x in @logger.transports
    @SIDE_EFFECTS = if enable then (@SIDE_EFFECTS or []) else null

  sideEffects: -> @SIDE_EFFECTS

Object.keys(levels).forEach (x) ->
  Logger::[x] = (xs...) -> if xs?[0] then @logger[x].apply(@logger, xs)

module.exports = new Logger()
