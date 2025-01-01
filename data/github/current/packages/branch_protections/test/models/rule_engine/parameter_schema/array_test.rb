# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEngineParameterSchemaArrayTest < GitHub::TestCase

  test "fails validation when parameter is not an array" do
    array = RuleEngine::ParameterSchema::Array.new(name: "string_list", display_name: "Foo", description: "Foo", content_type: :string, required: true)

    value = "foo"
    context = RuleEngine::ParameterSchema::ValidationContext.new(value, nil)
    assert_equal [{ error_code: :unexpected_type, message: "Expected array, got String" }], array.validate_parameters(context, value)
  end

  test "passes validation when parameter is an array" do
    array = RuleEngine::ParameterSchema::Array.new(name: "string_list", display_name: "Foo", description: "Foo", content_type: :string, required: true)

    value = ["foo"]
    context = RuleEngine::ParameterSchema::ValidationContext.new(value, nil)
    assert_equal [], array.validate_parameters(context, value)
  end

  test "passes validation when parameter's values match allowed options" do
    array = RuleEngine::ParameterSchema::Array.new(name: "enum_list", display_name: "Foo", description: "Foo", content_type: :string, required: true,
      allowed_options: [
        { value: "a", display_name: "A", description: "A value" },
        { value: "b", display_name: "B", description: "B value" }
      ])

    value = %w[a b]
    context = RuleEngine::ParameterSchema::ValidationContext.new(value, nil)
    assert_equal [], array.validate_parameters(context, value)
  end

  test "fails validation when parameter's values do not match allowed options" do
    array = RuleEngine::ParameterSchema::Array.new(name: "enum_list", display_name: "Foo", description: "Foo", content_type: :string, required: true,
      allowed_options: [
        { value: "a", display_name: "A", description: "A value" },
        { value: "b", display_name: "B", description: "B value" }
      ])

    value = %w[a b c]
    context = RuleEngine::ParameterSchema::ValidationContext.new(value, nil)
    assert_equal [{ error_code: :invalid_content, message: "Invalid option `c` at index 2. Allowed options are a, b", index: 2 }], array.validate_parameters(context, value)
  end
end
