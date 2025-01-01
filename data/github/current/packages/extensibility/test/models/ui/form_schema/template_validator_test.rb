# typed: true
# frozen_string_literal: true

require "test_helper"

class UI::FormSchema::TemplateValidatorTest < GitHub::TestCase
  test "expects a name and a body" do
    validator = UI::FormSchema::TemplateValidator.new({ name: nil })
    refute_predicate validator, :valid?
    assert_equal [
      "`name` was expected to be a `String` but was `NilClass`",
      "`body` was expected to an `Array` but was a `NilClass`"
    ], validator.errors.full_messages
  end

  test "expects the description field to be a String" do
    validator = UI::FormSchema::TemplateValidator.new({ name: "hello", description: 1, body: [] })
    refute_predicate validator, :valid?
    assert_equal ["`description` was expected to be a `String` but was `Integer`"], validator.errors.full_messages
  end

  test "has an description field" do
    validator = UI::FormSchema::TemplateValidator.new({ name: "hello", description: "What's all this description?", body: [] })
    assert_predicate validator, :valid?
  end

  test "is valid" do
    validator = UI::FormSchema::TemplateValidator.new({ name: "hello", body: [] })
    assert_predicate validator, :valid?
    assert_predicate validator.deprecation_warnings.full_messages, :empty?
  end

  test "errors the body index, when the form body has an error" do
    steps = [
      { name: "hello", body: [] },
      { name: "hello", body: ["a"] },
      { name: "hello", body: [{ type: "input", attributes: { label: "name" } }] },
    ]

    validator = UI::FormSchema::TemplateValidator.new(
      { name: "hello", body: [nil, "a", { type: "input", attributes: { name: "name" } }] }
    )
    refute_predicate validator, :valid?
    assert_equal [
      "`body[0]` was expected to be a `Hash` but was a `NilClass`",
      "`body[1]` was expected to be a `Hash` but was a `String`",
      "`body[2].attributes` `name` must be one of `label`, `id`, `description`, `placeholder`, `value`, or `format`",
    ], validator.errors.full_messages
  end
end
