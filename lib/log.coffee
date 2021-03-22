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
    lines         = info.message.split('\n').map((x) -> x.trimRight()).filter((x) -> x)
    message1      = color.bold("#{prog}: #{lines.shift()}")
    message2      = color(lines.join('\n')) if lines.length
    body          = stderr.dim(info.body) if info.body and verbose
    info[MESSAGE] = [message1, message2, body].filter((x) -> x).join('\n')
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
