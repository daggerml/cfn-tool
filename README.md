# NAME

`cfn-tool` &mdash; a cloudformation template processing and stack deployment tool.

# INSTALL

```bash
sudo npm install -g 'daggerml/cfn-tool#3.0.1'
```

# USAGE

See [the manual page][6] (or `man cfn-tool`) for complete usage and options info.

Expand macros in `template.yml` and print resulting YAML to stdout:

```bash
cfn-tool template.yml
```

Expand macros in my-template.yml and nested templates, lint and validate
templates, upload packages and templates to S3, and deploy `my-template.yml`
to `my-stack`:

```bash
cfn-tool template.yml my-stack
```

# TEMPLATE MACROS

The `cfn-tool` program provides preprocessor macros and handles the packaging,
compression, and upload of templates and zip files to S3 for use in
CloudFormation stacks.

> **Note:** The [tests][16] contain many examples of template macro usage.

### Short vs. Full Tags

Custom tags can be used as "short tags" or "full tags":

```yaml
# short tag
Foo: !Base64 bar
```
```yaml
# full tag
Foo:
  Fn::Base64: bar
```

## Top Level Macros

Top level macros are used at the top level of the template, to transform the
[main sections][17] of the template or to execute top level compiler commands.

### `!Require`

The `!Require` macro can be used to add global macro definitions to the parser.
Macro definitions are implemented in JavaScript or CoffeeScript, and are defined
in all templates, including nested ones.

```javascript
// ./lib/case-macros.js
module.exports = (compiler) => {
  compiler.defmacro('UpperCase', (form) => form.toUpperCase());
  compiler.defmacro('LowerCase', (form) => form.toLowerCase());
};
```
```yaml
# INPUT
<<: !Require ./lib/case-macros
Foo: !UpperCase AsDf
Bar: !LowerCase AsDf
```
```yaml
# OUTPUT
Foo: ASDF
Bar: asdf
```

The `!Require` macro also accepts an array of definition files:

```yaml
<<: !Require
  - ./lib/case-macros
  - ./lib/loop-macros
```

### `!Resources`

The basic [CloudFormation resource structure][1] has the following form:

```yaml
Resources:
  <LogicalID>:
    Type: <ResourceType>
    Properties:
      <PropertyKey>: <PropertyValue>
```

The `!Resources` macro resource DSL has the following slightly different
form:

```yaml
<<: !Resources
  <LogicalID> <ResourceType>:
    <PropertyKey>: <PropertyValue>
```

The macro resource DSL also includes top-level fields (eg. [`Condition`][18],
[`DependsOn`][19], etc.) which may be included as `<Field>=<Value>` pairs:

```yaml
# INPUT
<<: !Resources
  Asg AWS::AutoScaling::AutoScalingGroup Condition=Create DependsOn=[Bar,Baz]:
    AutoScalingGroupName: !Sub '${Zone}-Asg'
    LaunchConfigurationName: !Ref MyServiceLaunchConfig
```
```yaml
# OUTPUT
Resources:
  Asg:
    Type: AWS::AutoScaling::AutoScalingGroup
    Condition: Create
    DependsOn:
      - Bar
      - Baz
    Properties:
      AutoScalingGroupName: !Sub '${Zone}-Asg'
      LaunchConfigurationName: !Ref MyServiceLaunchConfig
```

### `!Let`

This section binds arbitrary YAML expressions to names local to this template.
The names are referenced by the built-in `!Ref` tag &mdash; the reference is
replaced by the bound expression. This works in all constructs supporting
`!Ref`, eg. in `!Sub` interpolated variables, etc.

```yaml
# INPUT
<<: !Let
  MyBinding: !If [ SomeCondition, Baz, !Ref Baf ]
Foo: !Ref MyBinding
```
```yaml
# OUTPUT
Foo: !If [ SomeCondition, Baz, !Ref Baf ]
```

> **Note:** References in the values of the `Fn::Let` form are
> [dynamic bindings][13], see [`!Let`](#let) below.

### `!Parameters`

This section is handy for reducing boilerplate in the [parameters section of a
CloudFormation template][21]. The value associated with this key is an array of
parameter names and options, with sensible defaults.

```yaml
# INPUT
<<: !Parameters
  - Zone
  - Subnets Type=CommaDelimitedList
  - Enabled Default=true AllowedValues=[true,false]
```
```yaml
# OUTPUT
Parameters:
  Zone:
    Type: String
  Subnets:
    Type: CommaDelimitedList
  Enabled:
    Type: String
    Default: true
    AllowedValues:
      - true
      - false
```

### `!Return`

The return section populates the [CloudFormation outputs boilerplate][22]
from a simple map of keys and values.

```yaml
# INPUT
<<: !Return
  Key1: !Ref Val1
  Key2: !Ref Val2
```
```yaml
# OUTPUT
Outputs:
  Key1:
    Value:
      Ref: Val1
  Key2:
    Value:
      Ref: Val2
```

## Templates, Packages, And Files

Some CloudFormation resources (eg. [nested stacks][5], [Lambda functions][14])
refer to other resources that must be uploaded to S3. The [`!Package`](#package)
macro and associated convenience macros based on it are provided to make this
easier.

### `!Package`

This macro uploads a file or directory to S3 and returns an object with the
`S3Bucket` and `S3Key` of the uploaded file. Directories are zipped before
upload. The argument can be a path (string) or an options object with the
following properties:

* **`Path`** &mdash; The path of the file/directory to upload, relative to this template.
* **`Parse`** &mdash; If `true`, recursively parse the file and expand macros before packaging (and after building).
* **`CacheKey`** &mdash; Filename in S3 will be computed from this string instead of from the hash of the contents.

A simple example:

```yaml
# INPUT
Foop: !Package foo/
```
```yaml
# OUTPUT
Foop:
  S3Bucket: mybucket
  S3Key: 6806d30eed132b19183a51be47264629.zip
```

### `!PackageURL`

This macro calls `!Package` and transforms the result to an S3 URL.

```yaml
# INPUT
Foop: !PackageURL foo/
```
```yaml
# OUTPUT
Foop: https://s3.amazonaws.com/mybucket/6806d30eed132b19183a51be47264629.zip
```

### `!PackageURI`

This macro calls `!Package` and transforms the result to an S3 URI.

```yaml
# INPUT
Foop: !PackageURI foo/
```
```yaml
# OUTPUT
Foop: s3://mybucket/6806d30eed132b19183a51be47264629.zip
```

### `!PackageTemplateURL`

This macro calls `!PackageURL` with `Parse` set to `true`.

```yaml
# INPUT
Foop: !PackageTemplateURL infra/mytemplate.yml
```
```yaml
# OUTPUT
Foop: https://s3.amazonaws.com/mybucket/6806d30eed132b19183a51be47264629.yaml
```

### `!TemplateFile`

This macro parses and recursively expands macros in a local YAML file, and then
merges the resulting data into the document. For example, suppose there is a
local file with the following YAML contents:

```yaml
# foo/config.yml
Foo:
  Bar: baz
```

Another template may import the contents of this file:

```yaml
# INPUT
Config: !TemplateFile foo/config.yml
```
```yaml
# OUTPUT
Config:
  Foo:
    Bar: baz
```

A nice trick is to combine a few macros to pull in default mappings which can
be overridden in the template:

```yaml
# config/prod.yml
Map1:
  us-east-1:
    Prop1: foo
    Prop2: bar
```
```yaml
# config/test.yml
!DeepMerge
  - !TemplateFile prod.yml
  - Map1:
      us-east-1:
        Prop2: baz
```
```yaml
# infra/my-stack.yml
Mappings:
  !TemplateFile ../config/${$Zone}.yml
```

## References

These macros reduce the boilerplate associated with references of various kinds
in CloudFormation templates.

### `!Attr`

Expands to a [`Fn::GetAtt`][8] expression with [`Fn::Sub`][4] interpolation on
the dot path segments.

```yaml
# INPUT
Foo: !Attr Thing.${Bar}
```
```yaml
# OUTPUT
Foo: { Fn::GetAtt: [ Thing, { Ref: Bar } ] }
```

### `!Env`

Expands to the value of an environment variable in the environment of the
preprocessor process. An exception is thrown if the variable is unset.

```yaml
# INPUT
Foo: !Env EDITOR
```
```yaml
# OUTPUT
Foo: vim
```

### `!Get`

Expands to an expression using [`Fn::FindInMap`][11] to look up a value from a
[template mapping structure][12]. References are interpolated in the argument
and dots are used to separate segments of the path (similar to [`Fn::GetAtt`][8]).

```yaml
# INPUT
Foo: !Get Config.${AWS::Region}.ImageId
```
```yaml
# OUTPUT
Foo:
  Fn::FindInMap:
    - Config
    - Ref: AWS::Region
    - ImageId
```

### `!Var`

Expands to a [`Fn::ImportValue`][3] call with a nested [`Fn::Sub`][4] to
perform variable interpolation on the export name.

```yaml
# INPUT
Resources:
  Foo:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Var ${Zone}-Foop
```
```yaml
# OUTPUT
Resources:
  Foo:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: { Fn::ImportValue: { Fn::Sub: ${Zone}-Foop } }
```

### `!Ref`

The builtin [`Ref`][7] intrinsic function is extended to support references to
environment variables, mappings, resource attributes, and bound names, in
addition to its normal functionality.

* **Environment variable references** start with `$` (see [`!Env`](#env) above).
* **Mapping attribute references** start with `%` (see [`!Get`](#get) above).
* **Resource attribute references** start with `@` (see [`!Attr`](#attr) above).
* **Bound names** are referenced with no prefix (see [`Fn::Let`](#fnlet) above).

```yaml
# INPUT
Foo: !Ref Zone
Bar: !Ref $USER
Baz: !Ref '%Config.${AWS::Region}.MainVpcSubnet'
Baf: !Ref '@Thing.Outputs.StreamName'
```
```yaml
# OUTPUT
Foo: { Ref: Zone }
Bar: micha
Baz: { Fn::FindInMap: [ Config, { Ref: AWS::Region }, MainVpcSubnet ] }
Baf: { Fn::GetAtt: [ Thing, Outputs.StreamName ] }
```

> **Note:** The `Ref` function is used by all other functions that support
> interpolation of references in strings, (eg. [`!Sub`][4], [`!Var`](#var),
> etc.) so these functions also support environment variable and resource
> attribute references.

## Other Useful Macros

### `!Do`

Given an array, sequentially expands macros in each item in the array, returning
the last result.

```yaml
# INPUT
Foo: !Do
  - !Let { Greet: world }
  - !Sub hello, ${Greet}!
```
```yaml
# OUTPUT
Foo: hello, world!
```

### `!Let`

The `!Let` macro can be used to expand simple templates within the template
file. The first argument is the bindings, the second is the template.

```yaml
# INPUT
Fn::Let:
  Template:
    IAm: a person
    MyNameIs: !Ref Name
    MyAgeIs: !Ref Age

Foo: !Let
  - Name: alice
    Age: 100
  - !Ref Template
```
```yaml
# OUTPUT
Foo:
  IAm: a person
  MyNameIs: alice
  MyAgeIs: 100
```

### `!Shell`

Given a shell script string, evaluates it in the shell, returning the output.
If the output ends with a newline character it is removed (only a single
trailing newline is removed &mdash; add an extra newline to the end to preserve
the final newline character in the output).

```yaml
# INPUT
Foo: !Shell echo hello, world!
```
```yaml
# OUTPUT
Foo: hello, world!
```

### `!Merge`

Performs a shallow merge of two or more maps, at compile time:

```yaml
# INPUT
Foo: !Merge
  - Uno: 1
  - Dos: 2
    Tres: 3
```
```yaml
# OUTPUT
Foo:
  Uno: 1
  Dos: 2
  Tres: 3
```

### `!DeepMerge`

Like `!Merge`, but performs a deep merge:

```yaml
# INPUT
Foo: !DeepMerge
  - Numeros:
      Uno: 1
      Dos: 2
      Cuatro: 4
  - Numeros:
      Dos: two
      Tres: three

```
```yaml
# OUTPUT
Foo:
  Numeros:
    Uno: 1
    Dos: two
    Tres: three
    Cuatro: 4
```

### `!File`

Reads a local file and returns its contents as a string.

```yaml
# INPUT
Script: !File doit.sh
```
```yaml
# OUTPUT
Script: |
  #!/bin/bash
  name=joe
  echo "hello, $name"
```

### `!JsonParse`, `!JsonDump`

```yaml
# INPUT
Foo1: !JsonParse '{"Bar":{"Baz":"baf"}}'
Foo2: !JsonDump
  Bar:
    Baz: baf
```
```yaml
# OUTPUT
Foo1:
  Bar:
    Baz: baf
Foo2: '{"Bar":{"Baz":"baf"}}'
```

### `!YamlParse`, `!YamlDump`

```yaml
# INPUT
Foo1: !YamlParse |
  Bar:
    Baz: baf
Foo2: !YamlDump
  Bar:
    Baz: baf
```
```yaml
# OUTPUT
Foo1:
  Bar:
    Baz: baf
Foo2: |
  Bar:
    Baz: baf
```

### `!Tags`

Expands a map to a list of [resource tag structures][2].

```yaml
# INPUT
Resources:
  Foo AWS::S3::Bucket:
    BucketName: foo-bucket
    Tags: !Tags
      ThreatLevel: infinity
      Maximumness: enforced
```
```yaml
# OUTPUT
Resources:
  Foo:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: foo-bucket
      Tags:
        - Key: ThreatLevel
          Value: infinity
        - Key: Maximumness
          Value: enforced
```

[1]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/resources-section-structure.html
[2]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-resource-tags.html
[3]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-importvalue.html
[4]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-sub.html
[5]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-stack.html
[6]: http://htmlpreview.github.io/?https://github.com/daggerml/cfn-tool/blob/3.0.1/man/cfn-tool.1.html
[7]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-ref.html
[8]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-getatt.html
[9]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-transform.html
[10]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/create-reusable-transform-function-snippets-and-add-to-your-template-with-aws-include-transform.html 
[11]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-findinmap.html
[12]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/mappings-section-structure.html
[13]: https://www.gnu.org/software/emacs/manual/html_node/elisp/Dynamic-Binding.html
[14]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-lambda-function.html
[15]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-stack.html#cfn-cloudformation-stack-templateurl
[16]: test/cfn-transformer/cfn-transformer.tests.yaml
[17]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-anatomy.html
[18]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/conditions-section-structure.html
[19]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-attribute-dependson.html
[20]: none
[21]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/parameters-section-structure.html
[22]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/outputs-section-structure.html
