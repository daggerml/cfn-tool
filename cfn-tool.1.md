cfn-tool(1) -- cloudformation template process and stack deploy
===============================================================

## SYNOPSIS

`cfn-tool` [`-h`|`--help`|`-V`|`--version`]<br>
`cfn-tool` [<options>...] <template-file> [<stack-name>]

## DESCRIPTION

When a <stack-name> is specified `cfn-tool` deploys the template <template-file>
to the cloudformation stack <stack-name>. If no stack named <stack-name> exists
one is created. Otherwise, the existing stack is updated.

Each raw template file is processed as follows: macros are expanded, nested
templates are recursively processed, packages are prepared for upload, and
their S3 URIs are computed. The processed template is then linted (optionally)
and validated with the AWS CloudFormation API.

When all templates have been successfully processed, any nested templates are
uploaded to S3 with their associated packages and the stack is deployed.

When no <stack-name> is specified, macros in the <template-file> are expanded,
the resulting YAML is printed to `stdout`, and the program exits. No nested
templates are processed, no packages are prepared, no linting or validation is
performed, and no stack is deployed. This can be useful for debugging.

## OPTIONS

Options are configured in the following ways (from lowest to highest priority):
configuration file, environment variables, and command line options.

Each command line option (except for `--profile` and `--region`) is associated
with a corresponding environment variable according to the following pattern:
the `--bucket` option, for example, is associated with the `CFN_TOOL_BUCKET`
environment variable. The `--profile` and `--region` options are special
&mdash; they are associated with the AWS environment variables `AWS_PROFILE`
and `AWS_DEFAULT_REGION`.

Environment variables associated with boolean options must have a value of
either `true` or `false`. String options are specified identically via the
command line and environment variables.

Options provided via the command line will be automatically exported as their
corresponding environment variables, and will be in the environment of any
shell commands executed during macro expansion. For example, when the
`--profile` option is specified on the command line there is no need to use it
in shell commands using the `aws`(1) CLI tool, as the `AWS_PROFILE` environment
variable is exported by `cfn-tool` to the environment in which the shell
commands are executed.

  * `-b`, `--bucket`=<name>:
    Upload templates to the S3 bucket given by <name>. A bucket must be
    specified when nested stacks are used, or when the template specified by
    <template-name> is more than 51KiB in size.

  * `-c`, `--config`=<file>:
    Specify the config file to use. If this option is not specified `cfn-tool`
    will look for a file named `.cfn-tool` in the current directory. This file
    will be sourced in the `bash`(1) shell. Environment variables defined here
    will be applied as default options.

  * `-k`, `--keep`:
    Don't delete the temporary directory to which processed templates are
    written when `cfn-tool` exits. This can be useful for debugging.

  * `-l`, `--linter`=<command>:
    Run <command> on each processed template file, aborting if the <command>
    fails. The template file path is appended to the <command> string and the
    resulting command line is evaluated in the `bash`(1) shell. The working
    directory is set to the directory in which the `cfn-tool` program was run.

  * `-p`, `--parameters`="<key>=<value> [<key>=<value> ...]":
    Set template input parameter overrides. When updating an existing stack the
    values of any unspecified parameters will be preserved.

  * `-p`, `--profile`=<name>:
    Use the AWS profile given by <name> to configure the AWS credentials
    provider chain.

  * `-q`, `--quiet`:
    Suppress all informational, diagnostic, and warning output.

  * `-r`, `--region`=<name>:
    Use the AWS region given by <name> for all AWS API calls.

  * `-t`, `--tags`="<key>=<value> [<key>=<value> ...]":
    A list of tags to associate with the stack that is created or updated. AWS
    CloudFormation also propagates these tags to resources in the stack if the
    resource supports it.

  * `-v`, `--verbose`:
    Print extra diagnostic output while processing.

## EXAMPLES

Using `cfn-lint`(1) to lint processed templates:

    $ cfn-tool --linter "cfn-lint -f pretty" my-template.yml my-stack

Specifying tags and parameters as key-value pairs:

    $ cfn-tool --tags "Foo=bar Baz=baf" my-template.yml my-stack
    $ cfn-tool --parameters "Foo=bar Baz=baf" my-template.yml my-stack

## ENVIRONMENT

Each command line option is associated with a corresponding environment
variable. See the `OPTIONS` section above.

## FILES

The `cfn-tool` program will look for a configuration file specified by the
`--config` option, the `CFN_TOOL_CONFIG` environment variable, or the default
`.cfn-tool` file in the current working directory. When this file exists it is
sourced in the `bash`(1) shell and any configuration environment variables
defined are used as defaults. Here is an example configuration file:

    CFN_TOOL_BUCKET=my-infra-${AWS_DEFAULT_REGION:?}
    CFN_TOOL_KEEP=true
    CFN_TOOL_LINTER="cfn-lint -f pretty -i W1007 --"
    CFN_TOOL_PARAMETERS="Zone=${ZONE:?} Service=RestAPI"
    CFN_TOOL_TAGS="Zone=${ZONE:?} Service=RestAPI"

Note that environment variables associated with options specified on the
command line, such as the `AWS_DEFAULT_REGION` variable above (associated with
the `--region` command line option), are defined in the environment in which
the configuration file is evaluated when that command line option is specified.

## EXIT STATUS

Exits with a status of 1 if an error occurred, or 0 otherwise.

## BUGS

Please open an issue: <https://github.com/daggerml/cfn-tool/issues>.

## COPYRIGHT

Copyright © 2021 Micha Niskin `<micha.niskin@gmail.com>`, distributed under
the following license:

* <https://github.com/daggerml/cfn-tool/blob/3.1.1/LICENSE>

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
