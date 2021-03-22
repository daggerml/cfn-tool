cfn-tool(1) -- cloudformation template process and stack deploy
===============================================================

## SYNOPSIS

`cfn-tool` [`-h`|`--help`]<br>
`cfn-tool` `transform` [<options>...] <template-file><br>
`cfn-tool` `deploy` [<options>...] <template-file> [<stack-name>]

## COMMANDS

Deploys cloudformation stack <stackname>, where <stackname> is of the format
<zone>-<template>. The <zone> must correspond to a configuration file named
config/<zone>.yml and the <template> must correspond to a cloudformation
template named infra/<template>.yml.

### transform

Given a <template-file>, expands macros in the template and prints the
result YAML to stdout.

Options:

  * `-q`, `--quiet`:
    Suppress all diagnostic output and warnings.

  * `-v`, `--verbose`:
    Print diagnostic output while processing.

### deploy

Deploys <template-file> to the cloudformation stack <stack-name>. If no stack
named <stack-name> exists one is be created. Otherwise the existing stack is
updated.

When no <stack-name> is specified a dry run is performed, where all templates
are transformed, packaged, linted, and validated, but no templates or packages
are uploaded to S3 and no stack is created or updated.

Options:

  * `-b`, `--bucket`=<name>:
    Upload templates to the S3 bucket given by <name>. This option overrides
    the `CFN_TOOL_BUCKET` environment variable. (See the `ENVIRONMENT` section
    below.)

  * `-l`, `--linter`=<command>:
    Run <command> on each processed template, aborting if the <command> fails.
    The template file path will be appended to the <command> and run in
    `bash`(1). Paths are relative to the directory in which the `cfn-tool`
    program is run.

  * `-P`, `--parameters`=<key>=<value>[,<key>=<<value>,...]:
    Set template input parameter overrides. When updating an existing stack the
    values of any unspecified parameters will be preserved.

  * `-p`, `--profile`=<name>:
    Use the AWS profile given by <name>.

  * `-q`, `--quiet`:
    Suppress all diagnostic output and warnings.

  * `-r`, `--region`=<name>:
    Use the AWS region given by <name>. This option overrides the `AWS_REGION`
    and `AWS_DEFAULT_REGION` environment variables. (See the `ENVIRONMENT`
    section below.)

  * `-t`, `--tags`=<key>=<value>[,<key>=<<value>,...]:
    A list of tags to associate with the stack that is created or updated. AWS
    CloudFormation also propagates these tags to resources in the stack if the
    resource supports it.

  * `-v`, `--verbose`:
    Print diagnostic output while processing.

## ENVIRONMENT

The following environment variables may be used in lieu of profiles for the
AWS credentials provider chain.

  * `AWS_DEFAULT_REGION`, `AWS_REGION`:
    The AWS region. These variables are set automatically when the `--region`
    option is specified. Either of the above can be set in the environment
    when the `--region` option is not specified (there are two because of an
    inconsistency between the AWS CLI tools and the provider chain in the AWS
    SDK, sometimes you need the one, sometimes the other -- the tool will copy
    whichever one you set to the other one).

  * `AWS_ACCESS_KEY_ID`:
    The AWS access key identifier (ie. 'AKIAXXXXXXXXXXXXXXXX').

  * `AWS_SECRET_ACCESS_KEY`:
    The AWS secret key.

Additionally, the following environment variables may be used to configure
the program.

  * `CFN_TOOL_BUCKET`:
    The name of the S3 bucket to which template files and packages will be
    uploaded. Overridden by the `-b`, `--bucket` option (see `deploy` above).

## EXIT STATUS

Exits with a status of 1 if an error occurred, or 0 otherwise.
