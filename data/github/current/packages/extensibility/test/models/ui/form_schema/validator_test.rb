# typed: true
# frozen_string_literal: true


require "test_helper"

class UI::FormSchema::ValidatorTest < GitHub::TestCase
  test "expects an array" do
    [1, "foo", {}, true, nil].each do |val|
      validator = UI::FormSchema::Validator.new(val, base_key: "schema")
      refute_predicate validator, :valid?
      assert_equal ["`schema` was expected to an `Array` but was a `#{val.class}`"], validator.errors.full_messages
      assert_predicate validator.deprecation_warnings.full_messages, :empty?
    end
  end

  test "expects an array of hashes" do
    validator = UI::FormSchema::Validator.new([1], base_key: "schema")
    refute_predicate validator, :valid?
    assert_equal ["`schema[0]` was expected to be a `Hash` but was a `Integer`"], validator.errors.full_messages
    assert_predicate validator.deprecation_warnings.full_messages, :empty?
  end

  test "errors fine without a base_key" do
    validator = UI::FormSchema::Validator.new([1])
    refute_predicate validator, :valid?
    assert_equal ["`[0]` was expected to be a `Hash` but was a `Integer`"], validator.errors.full_messages
    assert_predicate validator.deprecation_warnings.full_messages, :empty?
  end

  test "expects and array of hashes with type and attributes" do
    validator = UI::FormSchema::Validator.new([{ type: "input" }], base_key: "schema")
    refute_predicate validator, :valid?
    assert_equal ["`schema[0]` was expected to include the key `attributes`"], validator.errors.full_messages
    assert_predicate validator.deprecation_warnings.full_messages, :empty?
  end

  test "expects type to be a string" do
    validator = UI::FormSchema::Validator.new([{ type: true, attributes: {} }], base_key: "schema")
    refute_predicate validator, :valid?
    assert_equal ["`schema[0].type` was expected to be a `String` but it was a `TrueClass`"], validator.errors.full_messages
    assert_predicate validator.deprecation_warnings.full_messages, :empty?
  end

  test "expects attributes to be a hash" do
    validator = UI::FormSchema::Validator.new([{ type: "input", attributes: "with ketchup" }], base_key: "schema")
    refute_predicate validator, :valid?
    assert_equal ["`schema[0].attributes` was expected to be a `Hash` but it was a `String`"], validator.errors.full_messages
    assert_predicate validator.deprecation_warnings.full_messages, :empty?
  end

  test "expects attributes to be not nil" do
    validator = UI::FormSchema::Validator.new([{ type: "input" }], base_key: "schema")
    refute_predicate validator, :valid?
    assert_equal ["`schema[0]` was expected to include the key `attributes`"], validator.errors.full_messages
    assert_predicate validator.deprecation_warnings.full_messages, :empty?
  end

  test "expects only certain top level keys" do
    validator = UI::FormSchema::Validator.new([{ type: "input", attributes: {}, validations: {}, foo: "" }], base_key: "schema")
    refute_predicate validator, :valid?
    assert_equal [
      "`schema[0]` was not expected to include the key `foo`",
      "`schema[0].attributes` was expected to have the key `label`"
    ], validator.errors.full_messages
    assert_predicate validator.deprecation_warnings.full_messages, :empty?
  end

  test "validates markdown has string value" do
    validator = UI::FormSchema::Validator.new([{ type: "markdown", attributes: { value: true } }], base_key: "schema")
    refute_predicate validator, :valid?
    assert_equal ["`schema[0].attributes.value` was expected to be a `String` but it was a `TrueClass`"], validator.errors.full_messages
    assert_predicate validator.deprecation_warnings.full_messages, :empty?
  end

  test "validates markdown value is not blank" do
    validator = UI::FormSchema::Validator.new([{ type: "markdown", attributes: { value: "" } }], base_key: "schema")
    refute_predicate validator, :valid?
    assert_equal ["`schema[0].attributes` was expected to have the key `value`"], validator.errors.full_messages
    assert_predicate validator.deprecation_warnings.full_messages, :empty?
  end

  test "validates valid types" do
    validator = UI::FormSchema::Validator.new([{ type: "foo", attributes: {}, validations: {} }], base_key: "schema")
    refute_predicate validator, :valid?
    assert_equal ["`schema[0].type` is not a valid type: `foo`"], validator.errors.full_messages
    assert_predicate validator.deprecation_warnings.full_messages, :empty?
  end

  test "validates `validations` is a `Hash`" do
    validator = UI::FormSchema::Validator.new([{ type: "input", attributes: { label: "nice" }, validations: "not_a_hash" }], base_key: "schema")
    refute_predicate validator, :valid?
    assert_equal ["`schema[0].validations` was expected to be a `Hash` but it was a `String`"], validator.errors.full_messages
    assert_predicate validator.deprecation_warnings.full_messages, :empty?
  end

  test "detects duplicate labels" do
    validator = UI::FormSchema::Validator.new(
      [
        { type: "input", attributes: { label: "name" }, validations: {} },
        { type: "input", attributes: { label: "name" }, validations: {} },
        { type: "input", attributes: { label: nil }, validations: {} },
        { type: "input", attributes: { label: true }, validations: {} },
        { type: "input", attributes: { label: "name" }, validations: {} }
      ],
      base_key: "schema"
    )
    refute_predicate validator, :valid?
    assert_equal [
      "`schema[2].attributes` was expected to have the key `label`",
      "`schema[3].attributes.label` was expected to be a `String` but it was a `TrueClass`",
      "`schema[0].label` was not unique",
      "`schema[1].label` was not unique",
      "`schema[4].label` was not unique"
    ], validator.errors.full_messages
    assert_predicate validator.deprecation_warnings.full_messages, :empty?
  end

  test "valid when there are markdown duplicates" do
    validator = UI::FormSchema::Validator.new(
      [
        { type: "markdown", attributes: { value: "hello world" } },
        { type: "markdown", attributes: { value: "hello world" } },
      ],
      base_key: "schema"
    )
    assert_predicate validator, :valid?
    assert_predicate validator.deprecation_warnings.full_messages, :empty?
  end

  test "limits_fields_to_25" do
    form_schema = 27.times.map { |i| { type: "input", attributes: { label: "name#{i}" } } }
    validator = UI::FormSchema::Validator.new(form_schema, base_key: "schema")
    refute_predicate validator, :valid?
    assert_equal [
      "`schema` is currently limited to `25` fields, but you currently have `27`. Please remove at least `2` fields.",
    ], validator.errors.full_messages
    assert_predicate validator.deprecation_warnings.full_messages, :empty?
  end
end
