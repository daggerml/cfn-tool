<!-- vim: set ft=markdown: -->
cfn-tool(1) -- extra tools for working with aws cloudformation
==============================================================

## SYNOPSIS

`cfn-tool` [`-h`|`--help`|`-V`|`--version`]<br>
`cfn-tool` *command* [*option*...] [*argument*...]

## DESCRIPTION

This program provides extra tools for working with AWS CloudFormation including
a template macro preprocessor, resource packaging, extended support for nested
stacks, additional stack deployment options (like template linting, for example),
and more.

## COMMANDS

The first argument to `cfn-tool` is the `command`. Each command has its own set
of options and required positional parameters, as described in its manual page.

## BASH COMPLETION

Add the following to your `bash`(1) configuration:

    complete -o default -C $(which cfn-tool-completer) cfn-tool

## SEE ALSO

Each command has its own man page:

* `cfn-tool-deploy`(1)
* `cfn-tool-transform`(1)
* `cfn-tool-update`(1)

## BUGS

Please open an issue: <https://github.com/daggerml/cfn-tool/issues>.

## COPYRIGHT

Copyright © ${YEAR} Micha Niskin `<micha.niskin@gmail.com>`, distributed under
the following license:

* <https://raw.githubusercontent.com/daggerml/cfn-tool/${VERSION}/LICENSE>

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
