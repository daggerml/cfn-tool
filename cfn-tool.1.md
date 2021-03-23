cfn-tool(1) -- cloudformation template process and stack deploy
===============================================================

## SYNOPSIS

`cfn-tool` [`-h`|`--help`|`-V`|`--version`]<br>
`cfn-tool` `transform` [<options>...] <template-file><br>
`cfn-tool` `deploy` [<options>...] <template-file> [<stack-name>]

## COMMANDS

The first argument to `cfn-tool` is the `command` &mdash; each command performs
an operation and has its own set of options specified by subsequent arguments.
Default values for command line options may be provided via environment
variables (see the `ENVIRONMENT` section below).

### transform

Given a <template-file>, expands macros in the template and prints the
result YAML to stdout.

Options:

  * `-b`, `--bucket`=<name>:
    Upload templates to the S3 bucket given by <name>. A bucket must be
    specified when nested stacks are used.

  * `-c`, `--config`=<file>:
    Specify the config file to use. If this option is not specified `cfn-tool`
    will look for a file named `.cfn-tool` in the current directory. This file
    will be sourced in the `bash`(1) shell and can be used to configure the
    various `CFN_TOOL_XXXX` environment variables.

  * `-k`, `--keep`:
    Don't delete the temporary directory to which processed templates are
    written when `cfn-tool` exits. This can be useful for debugging.

  * `-q`, `--quiet`:
    Suppress all informational, diagnostic, and warning output.


  * `-v`, `--verbose`:
    Print extra diagnostic output while processing.

### deploy

Deploys <template-file> to the cloudformation stack <stack-name>. If no stack
named <stack-name> exists one is be created. Otherwise the existing stack is
updated.

When no <stack-name> is specified a dry run is performed, where all templates
are transformed, packaged, linted, and validated, but no templates or packages
are uploaded to S3 and no stack is created or updated.

Options:

  * `-b`, `--bucket`=<name>:
    Upload templates to the S3 bucket given by <name>. A bucket must be
    specified when nested stacks are used, or when the template specified by
    <template-name> is more than 51KiB in size.

  * `-c`, `--config`=<file>:
    Specify the config file to use. If this option is not specified `cfn-tool`
    will look for a file named `.cfn-tool` in the current directory. This file
    will be sourced in the `bash`(1) shell and can be used to configure the
    various `CFN_TOOL_XXXX` environment variables.

  * `-k`, `--keep`:
    Don't delete the temporary directory to which processed templates are
    written when `cfn-tool` exits. This can be useful for debugging.

  * `-l`, `--linter`=<command>:
    Run <command> on each processed template, aborting if the <command> fails.
    The template file path will be appended to the <command> and run in
    `bash`(1). Paths are relative to the directory in which the `cfn-tool`
    program is run.

  * `-P`, `--parameters`=<key>=<value>[,<key>=<value>,...]:
    Set template input parameter overrides. When updating an existing stack the
    values of any unspecified parameters will be preserved.

  * `-p`, `--profile`=<name>:
    Use the AWS profile given by <name> to configure the AWS credentials
    provider chain.

  * `-q`, `--quiet`:
    Suppress all informational, diagnostic, and warning output.

  * `-r`, `--region`=<name>:
    Use the AWS region given by <name> for all AWS API calls.

  * `-t`, `--tags`=<key>=<value>[,<key>=<<value>,...]:
    A list of tags to associate with the stack that is created or updated. AWS
    CloudFormation also propagates these tags to resources in the stack if the
    resource supports it.

  * `-v`, `--verbose`:
    Print extra diagnostic output while processing.

## ENVIRONMENT

The following environment variables provide default values for command line
options. Command line options override these variables and `cfn-tools` sets
or updates these variables when all command line options have been parsed.

  * `AWS_PROFILE`:
    Provides a default value for the `--profile` option.

  * `AWS_REGION`, `AWS_DEFAULT_REGION`:
    Provides a default for the `--region` option. There are two region
    variables due to inconsistencies between various AWS APIs. Only one of them
    needs to be set &mdash; `cfn-tool` will set the other automatically.

  * `AWS_ACCESS_KEY_ID`:
    The AWS access key. Required when no profile is specified.

  * `AWS_SECRET_ACCESS_KEY`:
    The AWS secret key. Required when no profile is specified.

  * `CFN_TOOL_BUCKET`:
    Provides a default value for the `--bucket` option.

  * `CFN_TOOL_CONFIG`:
    Provides a default value for the `--config` option.

  * `CFN_TOOL_KEEP`:
    Provides a default value for the `--keep` option (`true` or `false`).

  * `CFN_TOOL_LINTER`:
    Provides a default value for the `--linter` option.

  * `CFN_TOOL_PARAMETERS`:
    Provides a default value for the `--parameters` option.

  * `CFN_TOOL_QUIET`:
    Provides a default value for the `--quiet` option (`true` or `false`).
    or `false`.

  * `CFN_TOOL_TAGS`:
    Provides a default value for the `--tags` option.

  * `CFN_TOOL_VERBOSE`:
    Provides a default value for the `--verbose` option (`true` or `false`).

## FILES

The following files are used to configure the `cfn-tool` program:

  * `.cfn-tool`:
    This file (if it exists in the project directory) is a `bash`(1) script
    sourced by `cfn-tool` to provide configuration settings as described in
    the `ENVIRONMENT` section above. This behavior is overridden by the
    `--config` command line option or the `CFN_TOOL_CONFIG` environment
    variable. Any `CFN_TOOL_XXXX` variables defined in this file will be
    applied as default configuration options.

## EXIT STATUS

Exits with a status of 1 if an error occurred, or 0 otherwise.
