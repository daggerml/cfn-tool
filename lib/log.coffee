{ createLogger, format, transports }  = require 'winston'
{ stderr }                            = require 'chalk'
{ MESSAGE }                           = require 'triple-beam'
{ basename }                          = require 'path'
prog                                  = basename(process.argv[1] or 'repl')

colors =
  error:    stderr.red
  warn:     stderr.yellow
  info:     stderr
  http:     stderr
  verbose:  stderr
  debug:    stderr
  silly:    stderr

priority =
  error:    0
  warn:     1
  info:     2
  http:     3
  verbose:  4
  debug:    5
  silly:    6

format = (
  format (info, opts) ->
    color         = colors[info.level]
    verbose       = priority[module.exports.level] > priority.info or
                    priority[info.level] < priority.info
    message       = color.bold("#{prog}: #{info.message}")
    body          = stderr.dim(info.body) if info.body and verbose
    info[MESSAGE] = if body then [ message, body ].join('\n') else message
    info
)()

transports = [
  new transports.Console(
    stderrLevels: [
      'error'
      'warn'
      'info'
      'http'
      'verbose'
      'debug'
      'silly'
    ]
  )
]

module.exports = createLogger { format, transports }
