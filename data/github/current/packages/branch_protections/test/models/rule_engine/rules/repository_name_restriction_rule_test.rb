# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryNameRestrictionRuleTest < GitHub::TestCase
  setup do
    @rule = RuleEngine::Rules::RepositoryNameRestrictionRule.new
  end

  test "valid regex patterns return no errors" do
    @rule_config = build(:repository_rule_configuration, rule_type: "repository_name", parameters: { pattern: ".*" })
    assert @rule.validate_parameterized(@rule_config).empty?
  end

  test "invalid regex patterns return errors" do
    @rule_config = build(:repository_rule_configuration, rule_type: "repository_name", parameters: { pattern: "**/*" })
    assert @rule.validate_parameterized(@rule_config).any?
  end
end
