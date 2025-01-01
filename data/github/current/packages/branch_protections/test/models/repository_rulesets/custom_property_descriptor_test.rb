# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRulesetsCustomPropertyDescriptorTests < GitHub::TestCase
  include RepositoryRulesets

  fixtures do
    @org = create :organization
    @repo = create :repository, owner: @org

    @definition_env = create :custom_property_definition, source: @org, property_name: "environment", description: "environment description"
    create :custom_property_value, target: @repo, definition: @definition_env, value: "test"
  end

  test "initialize" do
    custom_definition = CustomPropertyDescriptor.new(@definition_env)

    assert_equal "environment", custom_definition.property_name
    assert_equal "environment description", custom_definition.description
    assert_equal "custom", custom_definition.source
    assert_equal "string", custom_definition.value_type
    assert_nil custom_definition.allowed_values
    assert_equal "Property: environment", custom_definition.display_name
    assert_equal "note", custom_definition.icon
  end

  test "validate based in the property type" do
    custom_definition = CustomPropertyDescriptor.new(@definition_env)

    assert custom_definition.validate(["test"])
  end
end
