<!-- vim: set ft=markdown: -->
# NAME

`cfn-tool` &mdash; a cloudformation template processing and stack deployment tool.

# INSTALL

```bash
sudo npm install -g 'daggerml/cfn-tool#${VERSION}'
```

Add the following to your `~/.bashrc` to enable bash completion:

```bash
complete -o default -C $(which cfn-tool-completer) cfn-tool
```

# USAGE

Expand macros in `template.yml` and print resulting YAML to stdout:

```bash
cfn-tool transform template.yml
```

Expand macros in `my-template.yml` and nested templates, lint and validate
templates, upload packages and templates to S3, and deploy `my-template.yml`
to `my-stack`:

```bash
cfn-tool deploy template.yml my-stack
```

Update a parameter of an existing stack, preserving previous values of all
existing parameters not specified for update:

```bash
cfn-tool update --parameters "Foo=bar Baz=baf" my-stack
```

Simple macro example:

```bash
cat <<EOT |cfn-tool transform /dev/stdin
Foo: !Shell uuidgen -t
EOT
```
```yaml
Foo: 53480aea-8c46-11eb-a4b0-61c2b0470324
```

> **Note:** There are many macro usage examples in the [unit tests YAML file][6].

# MANUALS

See the manual pages for complete usage and options info:

* [cfn-tool(1)][1]
* [cfn-tool-deploy(1)][2]
* [cfn-tool-transform(1)][3]
* [cfn-tool-update(1)][4]

And the built-in macros reference manual page:

* [cfn-tool-macros(1)][5]

[1]: http://htmlpreview.github.io/?https://github.com/daggerml/cfn-tool/blob/${VERSION}/man/cfn-tool.html
[2]: http://htmlpreview.github.io/?https://github.com/daggerml/cfn-tool/blob/${VERSION}/man/cfn-tool-deploy.html
[3]: http://htmlpreview.github.io/?https://github.com/daggerml/cfn-tool/blob/${VERSION}/man/cfn-tool-transform.html
[4]: http://htmlpreview.github.io/?https://github.com/daggerml/cfn-tool/blob/${VERSION}/man/cfn-tool-update.html
[5]: http://htmlpreview.github.io/?https://github.com/daggerml/cfn-tool/blob/${VERSION}/man/cfn-tool-macros.html
[6]: https://github.com/daggerml/cfn-tool/blob/${VERSION}/test/macro.tests.yml
