# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleSettingsDependencyTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @org = create(:organization, admin: @owner)
    @org_repo = create(:repository, owner: @org)

    @ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
  end

  context "es_query_property_ruleset_conditions" do
    test "build query for a property ruleset" do
      create :custom_property_definition, source: @org, property_name: "environment"

      condition = create(:repository_rule_condition, target: "repository_property", parameters: {
        include: [{ name: "environment", property_values: ["testing"], source: "custom" }],
        exclude: []
      }, repository_ruleset: @ruleset)

      assert_equal @org.es_query_property_ruleset_conditions(condition), "org:#{@org.display_login} props.environment:testing"
    end

    test "build query for a property ruleset with exclude" do
      create :custom_property_definition, source: @org, property_name: "environment"
      create :custom_property_definition, source: @org, property_name: "language"

      condition = create(:repository_rule_condition, target: "repository_property", parameters: {
        include: [{ name: "environment", property_values: ["testing"], source: "custom" }],
        exclude: [{ name: "language", property_values: ["ruby"], source: "custom" }]
      }, repository_ruleset: @ruleset)

      assert_equal @org.es_query_property_ruleset_conditions(condition), "org:#{@org.display_login} props.environment:testing -props.language:ruby"
    end
  end

  context "build_phrase_from_property_condition" do
    test "quotes property values when url safe parameter is set" do
      create :custom_property_definition, source: @org, property_name: "environment"
      create :custom_property_definition, source: @org, property_name: "language"

      condition = create(:repository_rule_condition, target: "repository_property", parameters: {
        include: [{ name: "environment", property_values: ["testing 2"], source: "custom" }],
        exclude: [{ name: "language", property_values: ["ruby"], source: "custom" }]
      }, repository_ruleset: @ruleset)

      assert_equal @org.build_phrase_from_property_condition(condition), "props.environment:\"testing 2\" -props.language:ruby"
    end
  end
end
