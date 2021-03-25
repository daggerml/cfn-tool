// Generated by CoffeeScript 2.5.1
(function() {
  var AWS_VERSIONS, CfnError, CfnTransformer, VERSION, abort, abortOnException, allOpts, allVars, assert, assertOk, assoc, config2opt, fixRegion, fs, getVars, getopts, getoptsConfig, identity, inspect, log, opt2var, os, parseArgv, parseAwsVersion, parseConfig, parseKeyValArg, path, quit, selectKeys, setLogLevel, setVars, split, typeOf, usage, useVars, uuid, var2opt, version, yaml,
    indexOf = [].indexOf;

  fs = require('fs');

  os = require('os');

  path = require('path');

  uuid = require('uuid');

  ({inspect} = require('util'));

  getopts = require('getopts');

  yaml = require('js-yaml');

  ({
    strict: assert
  } = require('assert'));

  log = require('./lib/log');

  CfnError = require('./lib/CfnError');

  CfnTransformer = require('./lib/cfn-transformer');

  ({
    version: VERSION
  } = require('./package.json'));

  AWS_VERSIONS = [1, 2];

  identity = function(x) {
    return x;
  };

  assoc = function(xs, k, v) {
    xs[k] = v;
    return xs;
  };

  selectKeys = function(o, ks) {
    return Object.keys(o).reduce((function(xs, x) {
      if (indexOf.call(ks, x) >= 0) {
        return assoc(xs, x, o[x]);
      } else {
        return xs;
      }
    }), {});
  };

  split = function(str, sep, count = 2e308) {
    var n, toks;
    toks = str.split(sep);
    n = Math.min(toks.length, count) - 1;
    return toks.slice(0, n).concat(toks.slice(n).join(sep));
  };

  assertOk = function(x, msg, body) {
    if (!x) {
      throw new CfnError(msg, body);
    }
    return x;
  };

  quit = function(msg) {
    if (msg) {
      console.log(msg);
    }
    return process.exit(0);
  };

  abort = function(e) {
    var body;
    if (e.code === 'ENOENT') {
      e = new CfnError(e.message);
    }
    body = e instanceof CfnError ? e.body : e.body || e.stack;
    log.error(e.message, {body});
    return process.exit(1);
  };

  process.on('uncaughtException', abort);

  typeOf = function(thing) {
    return Object.prototype.toString.call(thing).slice(8, -1);
  };

  abortOnException = function(lib, fn) {
    return (typeOf(fn) === 'Array' ? fn : [fn]).forEach(function(x) {
      return global[x] = function(...args) {
        var e;
        try {
          return lib[x].apply(lib, args);
        } catch (error) {
          e = error;
          return abort(e);
        }
      };
    });
  };

  abortOnException(fs, ['writeFileSync', 'readFileSync', 'existsSync']);

  fixRegion = function() {
    var r1, r2;
    [r1, r2] = [process.env.AWS_REGION, process.env.AWS_DEFAULT_REGION];
    if (r1 && r2 && r1 !== r2) {
      process.env.AWS_REGION = r2;
    }
    if (r2 && !r1) {
      process.env.AWS_REGION = r2;
    }
    if (r1 && !r2) {
      return process.env.AWS_DEFAULT_REGION = r1;
    }
  };

  fixRegion();

  getoptsConfig = {
    alias: {
      bucket: 'b',
      config: 'c',
      help: 'h',
      keep: 'k',
      linter: 'l',
      parameters: 'P',
      profile: 'p',
      quiet: 'q',
      region: 'r',
      tags: 't',
      verbose: 'v',
      version: 'V'
    },
    boolean: ['help', 'keep', 'quiet', 'verbose', 'version'],
    string: ['bucket', 'config', 'linter', 'parameters', 'profile', 'region', 'tags'],
    unknown: function(x) {
      return abort(new CfnError(`unknown option: '${x}'`));
    }
  };

  opt2var = {
    bucket: 'CFN_TOOL_BUCKET',
    config: 'CFN_TOOL_CONFIG',
    help: 'CFN_TOOL_HELP',
    keep: 'CFN_TOOL_KEEP',
    linter: 'CFN_TOOL_LINTER',
    parameters: 'CFN_TOOL_PARAMETERS',
    profile: 'AWS_PROFILE',
    quiet: 'CFN_TOOL_QUIET',
    region: 'AWS_REGION',
    tags: 'CFN_TOOL_TAGS',
    verbose: 'CFN_TOOL_VERBOSE',
    version: 'CFN_TOOL_VERSION'
  };

  assert.deepEqual(new Set(Object.keys(opt2var)), new Set(getoptsConfig.boolean.concat(getoptsConfig.string)), "option->variable name mapping out of sync");

  var2opt = Object.keys(opt2var).reduce((function(xs, x) {
    return assoc(xs, opt2var[x], x);
  }), {});

  allOpts = Object.keys(opt2var);

  allVars = Object.keys(var2opt);

  useVars = Object.keys(var2opt).reduce(function(xs, x) {
    if (process.env[x] != null) {
      return xs.concat([x]);
    } else {
      return xs;
    }
  }, []);

  config2opt = function(k, v) {
    if (!(indexOf.call(getoptsConfig.boolean, k) >= 0)) {
      return v;
    } else {
      return v === 'true';
    }
  };

  getVars = function() {
    return allOpts.reduce(function(xs, x) {
      var v;
      v = process.env[opt2var[x]];
      if (v != null) {
        return assoc(xs, x, config2opt(x, v));
      } else {
        return xs;
      }
    }, {});
  };

  setVars = function(opts, clobber = false) {
    var o, v;
    for (o in opt2var) {
      v = opt2var[o];
      if ((opts[o] != null) && (clobber || !(indexOf.call(useVars, v) >= 0))) {
        process.env[v] = `${opts[o]}`;
      }
    }
    return fixRegion();
  };

  usage = function() {
    return quit(`See the manpage:
* cmd: man cfn-tool
* url: http://htmlpreview.github.io/?https://github.com/daggerml/cfn-tool/blob/${VERSION}/man/cfn-tool.1.html`);
  };

  version = function() {
    return quit(VERSION);
  };

  parseArgv = function(argv) {
    var opts;
    opts = getopts(argv, assoc(getoptsConfig, 'default', getVars()));
    switch (false) {
      case !opts.help:
        usage();
        break;
      case !opts.version:
        version();
        break;
      case !!argv.length:
        usage();
    }
    opts.template = opts._[0];
    opts.stackname = opts._[1];
    assertOk(opts.template, 'template argument required');
    if (!opts.stackname) {
      Object.assign(opts, {
        debug: true,
        bucket: 'example-bucket',
        s3bucket: 'example-bucket'
      });
    } else {
      Object.assign(opts, {
        dolint: true,
        dovalidate: true,
        dopackage: true,
        s3bucket: opts.bucket
      });
    }
    return opts;
  };

  parseAwsVersion = function(x) {
    var ref;
    return Number(x != null ? (ref = x.match(/^aws-cli\/([0-9]+)\./)) != null ? ref[1] : void 0 : void 0);
  };

  parseKeyValArg = function(x) {
    return x.split(/ /).map(function(x) {
      return `'${x}'`;
    }).join(' ');
  };

  parseConfig = function(x, uid) {
    var lines;
    lines = x.split('\n').map(function(x) {
      return x.trim();
    }).filter(identity);
    lines = lines.slice(lines.indexOf(uid) + 2);
    return lines.reduce(function(xs, line) {
      var k, v;
      [k, v] = split(line, '=', 2);
      k = var2opt[k];
      v = Buffer.from(v, 'base64').toString('utf-8');
      if (k) {
        return assoc(xs, k, config2opt(k, v));
      } else {
        return xs;
      }
    }, {});
  };

  setLogLevel = function(opts) {
    log.level = (function() {
      switch (false) {
        case !opts.verbose:
          return 'verbose';
        case !opts.quiet:
          return 'error';
        case !opts.debug:
          return 'warn';
        default:
          return 'info';
      }
    })();
    return opts;
  };

  module.exports = function() {
    var awsversion, bucketarg, cfg, cfgscript, cfn, e, exec, opts, paramsarg, res, tagsarg, tpl, uid;
    opts = setLogLevel(parseArgv(process.argv.slice(2)));
    cfn = new CfnTransformer(opts);
    exec = cfn.execShell.bind(cfn);
    cfg = opts.config || (existsSync('.cfn-tool') && '.cfn-tool');
    uid = uuid.v4();
    if (cfg) {
      log.verbose(`using config file: ${cfg}`);
      setVars(opts);
      cfgscript = readFileSync(cfg);
      try {
        setVars(parseConfig(exec(`. '${cfg}'
echo
echo ${uid}
for i in $(compgen -A variable |grep '^\\(AWS_\\|CFN_TOOL_\\)'); do
  echo $i=$(echo -n "\${!i}" |base64 -w0)
done`)));
      } catch (error) {
        e = error;
        e.message = e.message.split('\n').shift();
        throw e;
      }
      opts = setLogLevel(parseArgv(process.argv.slice(2)));
      cfn = new CfnTransformer(opts);
      exec = cfn.execShell.bind(cfn);
    }
    setVars(opts, true);
    cfn.tmpdir = fs.mkdtempSync([os.tmpdir(), 'cfn-tool-'].join('/'));
    process.on('exit', function() {
      if (!opts.keep) {
        return fs.rmdirSync(cfn.tmpdir, {
          recursive: true
        });
      }
    });
    log.verbose("configuration options", {
      body: inspect(selectKeys(opts, allOpts))
    });
    if (opts.stackname) {
      assertOk(exec('which aws', 'aws CLI tool not found on $PATH'));
    }
    awsversion = parseAwsVersion(exec('aws --version'));
    assertOk(indexOf.call(AWS_VERSIONS, awsversion) >= 0, `unsupported aws CLI tool version: ${awsversion} (supported versions are ${AWS_VERSIONS})`);
    log.info('preparing templates');
    res = cfn.writeTemplate(opts.template);
    tpl = readFileSync(res.tmpPath).toString('utf-8');
    if (opts.debug) {
      console.log(tpl.trimRight());
    } else if (opts.stackname) {
      if (res.nested.length > 1) {
        if (!opts.bucket) {
          throw new CfnError('bucket required for nested stacks');
        }
        log.info('uploading templates to S3');
        exec(`aws s3 sync --size-only '${cfn.tmpdir}' 's3://${opts.bucket}/'`);
      }
      if (opts.bucket) {
        bucketarg = `--s3-bucket '${opts.bucket}' --s3-prefix aws/`;
      }
      if (opts.parameters) {
        paramsarg = `--paramter-overrides ${parseKeyValArg(opts.parameters)}`;
      }
      if (opts.tags) {
        tagsarg = `--tags ${parseKeyValArg(opts.tags)}`;
      }
      log.info('deploying stack');
      exec(`aws cloudformation deploy --template-file '${res.tmpPath}' --stack-name '${opts.stackname}' --capabilities CAPABILITY_NAMED_IAM CAPABILITY_IAM CAPABILITY_AUTO_EXPAND ${bucketarg || ''} ${paramsarg || ''} ${tagsarg || ''}`);
    }
    log.info('done -- no errors');
    return quit();
  };

}).call(this);
