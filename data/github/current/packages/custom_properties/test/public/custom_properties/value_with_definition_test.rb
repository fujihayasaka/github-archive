# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomProperties::ValueWithDefinitionTest < GitHub::TestCase
  include CustomProperties

  fixtures do
    @org = create :organization, name: "main-org"
    @repo = create :repository, owner: @org, name: "main-repo"
  end

  test "constructor assigns correct values" do
    definition_env = create :custom_property_definition, source: @org, property_name: "environment"
    value_env = create :custom_property_value, definition: definition_env, target: @repo, value: "prod"

    definition_security = create :custom_property_definition, source: @org, property_name: "security", required: true, default_value: "high"
    value_security = create :custom_property_value, definition: definition_security, target: @repo, value: "low"

    no_default_no_value = ValueWithDefinition.new(definition_env, [])
    assert_nil no_default_no_value.manual_value
    assert_nil no_default_no_value.effective_value
    assert_equal definition_env, no_default_no_value.definition

    no_default_with_value = ValueWithDefinition.new(definition_env, [value_env])
    assert_equal value_env.value, no_default_with_value.manual_value
    assert_equal value_env.value, no_default_with_value.effective_value

    default_no_value = ValueWithDefinition.new(definition_security, [])
    assert_nil default_no_value.manual_value
    assert_equal definition_security.default_value, default_no_value.effective_value

    default_with_value = ValueWithDefinition.new(definition_security, [value_security])
    assert_equal value_security.value, default_with_value.manual_value
    assert_equal value_security.value, default_with_value.effective_value
  end

  test "equality" do
    definition_env = create :custom_property_definition, source: @org, property_name: "environment"
    value_env = create :custom_property_value, definition: definition_env, target: @repo, value: "prod"

    with_value = ValueWithDefinition.new(definition_env, [value_env])
    no_value = ValueWithDefinition.new(definition_env, [])

    assert_equal with_value, ValueWithDefinition.new(definition_env, [value_env])
    refute_equal with_value, no_value
  end
end
