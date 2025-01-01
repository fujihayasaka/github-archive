# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRulesetsCustomPropertiesTests < GitHub::TestCase
  include RepositoryRulesets::CustomProperties

  setup do
    @org = create :organization
    ruby = create(:language_name, name: "Ruby")
    @smile = create :repository, owner: @org, name: "smile", primary_language: ruby

    @definition_env = create :custom_property_definition, source: @org, property_name: "environment", description: "environment description"
    create :custom_property_value, target: @smile, definition: @definition_env, value: "test"
  end

  context "get_property_descriptors" do
    test "returns the collection definitions" do
      properties = RepositoryRulesets::CustomProperties.get_property_descriptors(@org)

      assert_equal properties.map(&:property_name), %w[fork language visibility environment]
      assert_equal properties.map(&:source), %w[system system system custom]
    end

    test "returns the get_allowed_values for the visibility property for a branch ruleset" do
      properties = RepositoryRulesets::CustomProperties.get_property_descriptors(@org)

      visibility_property = properties.find { |p| p.property_name == "visibility" }
      assert_equal visibility_property&.get_allowed_values("branch"), %w[public private internal]
    end

    test "returns the get_allowed_values for the visibility property for a push ruleset" do
      properties = RepositoryRulesets::CustomProperties.get_property_descriptors(@org)

      visibility_property = properties.find { |p| p.property_name == "visibility" }
      assert_equal visibility_property&.get_allowed_values("push"), %w[private internal]
    end
  end

  context "get_property_values" do
    %w[system custom].each do |source|
      test "returns empty if not property_names (#{source})" do
        assert_empty RepositoryRulesets::CustomProperties.get_property_values(@smile, source, [])
      end
    end

    test "raise if invalid source" do
      assert_raises(ArgumentError, 'Invalid source. Expected "system" or "custom"') do
        RepositoryRulesets::CustomProperties.get_property_values(@smile, "invalid", ["environment"])
      end
    end

    [{ name: "language", source: "custom" }, { name: "region", source: "system" }].each do |property|
      test "returns empty if property is not defined (#{property[:source]})" do
        assert_empty RepositoryRulesets::CustomProperties.get_property_values(@smile, property[:source], [property[:name]])
      end
    end

    test "returns the collection values for a single custom property_name" do
      values = RepositoryRulesets::CustomProperties.get_property_values(@smile, "custom", ["environment"])
      assert_equal values, { "environment" => "test" }
    end

    test "returns the collection values for multiple custom property_names" do
      create :custom_property_definition, source: @org, property_name: "language", required: true, default_value: "ruby"

      values = RepositoryRulesets::CustomProperties.get_property_values(@smile, "custom", %w[environment language])
      assert_equal values, { "environment" => "test", "language" => "ruby" }
    end

    test "property names are case insensitive. Resulted hash uses name stored in the ruleset as a key." do
      create :custom_property_definition, source: @org, property_name: "LANGUAGE", required: true, default_value: "ruby"

      values = RepositoryRulesets::CustomProperties.get_property_values(@smile, "custom", %w[environment language])
      assert_equal values, { "environment" => "test", "language" => "ruby" }
    end

    test "returns the collection values for multiple property_names" do
      values = RepositoryRulesets::CustomProperties.get_property_values(@smile, "system", %w[fork visibility language])
      assert_equal values, { "fork" => "false", "visibility" => TestEnv.test_with_all_emus? ? "internal" : "public", "language" => "Ruby" }
    end

    test "return collection values for a private repository" do
      private_repo = create(:private_repository, owner: @org)

      values = RepositoryRulesets::CustomProperties.get_property_values(private_repo, "system", %w[fork visibility language])
      assert_equal values, { "fork" => "false", "visibility" => "private", "language" => nil }
    end
  end
end
