assert          = require 'assert'
fn              = require '../lib/fn'

describe 'fn -- utility function unit tests', ->

  describe 'shprintf', ->
    fmt1 = """
      doit -f%{ -g %S} asdf
    """
    it 'should ignore null string format args', ->
      assert.equal(fn.shprintf(fmt1), 'doit -f asdf')

    it 'null string format args should throw when the arg has the ! modifier', ->
      assert.throws(
        -> fn.shprintf(fmt1.replace(/%S/, '%S!'))
        /missing required value/
      )

    it 'should interpolate a string format arg', ->
      assert.equal(fn.shprintf(fmt1, 'foop'), 'doit -f -g foop asdf')

    it 'should interpolate a string format arg with spaces in it', ->
      assert.equal(fn.shprintf(fmt1, 'foop with spaces'), "doit -f -g 'foop with spaces' asdf")

    it 'should interpolate a string format arg with double-quotes in it', ->
      assert.equal(
        fn.shprintf(fmt1, 'foop with "quotes"')
        "doit -f -g 'foop with \"quotes\"' asdf"
      )

    it 'should interpolate a string format arg with single-quotes in it', ->
      assert.equal(
        fn.shprintf(fmt1, "foop with 'quotes'")
        "doit -f -g \"foop with 'quotes'\" asdf"
      )

    it 'should interpolate a string format arg with both types of quotes in it', ->
      assert.equal(
        fn.shprintf(fmt1, "foop with \"both types of 'quotes'\"")
        "doit -f -g \"foop with \\\"both types of 'quotes'\\\"\" asdf"
      )

    fmt2 = """
      doit -f%{ -g %A} asdf
    """

    it 'should ignore null array format args', ->
      assert.equal(fn.shprintf(fmt2), 'doit -f asdf')

    it 'should interpolate array format args', ->
      assert.equal(fn.shprintf(fmt2, 'foop barp'), 'doit -f -g foop barp asdf')

    it 'should interpolate array format args with spaces in them', ->
      assert.equal(
        fn.shprintf(fmt2, 'asdf "qwer zxcv" poiu')
        "doit -f -g asdf 'qwer zxcv' poiu asdf"
      )
