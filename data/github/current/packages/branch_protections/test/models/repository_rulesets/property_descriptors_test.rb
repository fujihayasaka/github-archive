# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRulesetsPropertyDescriptorsTests < GitHub::TestCase
  include RepositoryRulesets::PropertyDescriptors

  setup do
    @org = create :organization
    ruby = create(:language_name, name: "Ruby")
    @smile = create :repository, owner: @org, name: "smile", primary_language: ruby

    @definition_env = create :custom_property_definition, source: @org, property_name: "environment", description: "environment description"
    create :custom_property_value, target: @smile, definition: @definition_env, value: "test"
  end

  context "get_descriptors" do
    test "returns the collection definitions" do
      properties = RepositoryRulesets::PropertyDescriptors.get_descriptors(@org)

      assert_equal properties.map(&:property_name), %w[fork language visibility environment]
      assert_equal properties.map(&:source), %w[system system system custom]
    end

    test "returns the get_allowed_values for the visibility property for a branch ruleset" do
      properties = RepositoryRulesets::PropertyDescriptors.get_descriptors(@org)

      visibility_property = properties.find { |p| p.property_name == "visibility" }
      assert_equal visibility_property&.get_allowed_values("branch"), %w[public private internal]
    end

    test "returns the get_allowed_values for the visibility property for a push ruleset" do
      properties = RepositoryRulesets::PropertyDescriptors.get_descriptors(@org)

      visibility_property = properties.find { |p| p.property_name == "visibility" }
      assert_equal visibility_property&.get_allowed_values("push"), %w[private internal]
    end
  end
end
