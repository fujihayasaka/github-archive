# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRulesetsSystemPropertiesTests < GitHub::TestCase
  include RepositoryRulesets::SystemProperties

  setup do
    @org = create :organization
    ruby = create(:language_name, name: "Ruby")
    @smile = create :repository, owner: @org, name: "smile", primary_language: ruby

    @definition_env = create :custom_property_definition, source: @org, property_name: "environment", description: "environment description"
    create :custom_property_value, target: @smile, definition: @definition_env, value: "test"
  end

  context "evaluate" do
    test "single system property" do
      assert RepositoryRulesets::SystemProperties.evaluate(@smile, [{ "name" => "fork", "property_values" => %w[false] }])
      refute RepositoryRulesets::SystemProperties.evaluate(@smile, [{ "name" => "fork", "property_values" => %w[true] }])
    end

    test "multiple system properties" do
      assert RepositoryRulesets::SystemProperties.evaluate(@smile, [{ "name" => "fork", "property_values" => %w[false] }, { "name" => "language", "property_values" => %w[Ruby] }])
      assert RepositoryRulesets::SystemProperties.evaluate(@smile, [{ "name" => "fork", "property_values" => %w[false] }, { "name" => "language", "property_values" => %w[Ruby Python] }])
    end

    test "multiple system properties with any match" do
      assert RepositoryRulesets::SystemProperties.evaluate(@smile, [{ "name" => "fork", "property_values" => %w[false] }, { "name" => "language", "property_values" => %w[Go] }], any_match: true)
    end

    test "evaluate when case insensitive" do
      assert RepositoryRulesets::SystemProperties.evaluate(@smile, [{ "name" => "fork", "property_values" => %w[false] }, { "name" => "language", "property_values" => %w[RUBY] }])
    end
  end
end
