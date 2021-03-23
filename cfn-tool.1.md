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

When all templates have been successfully processed they are uploaded to S3
along with their associated packages, and the stack is deployed.

When no <stack-name> is specified macros in the <template-file> are expanded,
the resulting YAML is printed to `stdout`, and the program exits. In this case
no nested templates are processed, no packages are prepared, and no linting
or validation is performed.

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

  * `-t`, `--tags`=<key>=<value>[,<key>=<value>,...]:
    A list of tags to associate with the stack that is created or updated. AWS
    CloudFormation also propagates these tags to resources in the stack if the
    resource supports it.

  * `-v`, `--verbose`:
    Print extra diagnostic output while processing.

## ENVIRONMENT

Each command line option is associated with a corresponding environment
variable. See the `OPTIONS` section above.

## FILES

  * `.cfn-tool`:
    The default configuration file. See the `--config` option above.

## EXIT STATUS

Exits with a status of 1 if an error occurred, or 0 otherwise.

## BUGS

Please open an issue: <https://github.com/daggerml/cfn-tool/issues>.

## COPYRIGHT

Copyright © 2021 Micha Niskin `<micha.niskin@gmail.com>`, distributed under
the following license:

* <https://github.com/daggerml/cfn-tool/blob/2.0.1/LICENSE>

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
