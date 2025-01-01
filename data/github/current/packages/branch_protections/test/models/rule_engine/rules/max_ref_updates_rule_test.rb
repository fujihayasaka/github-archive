# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEnginePushesMaxRefUpdatesRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @repo = create(:repository)
  end

  setup do
    ref_updates = [
      create_branch_update(@repo, name: "main"),
      create_branch_update(@repo, name: "develop"),
    ]

    @context = RuleEngine::RuleEvaluationContext.new(@repo)

    @rule_config = build(
      :repository_rule_configuration,
      rule_type: "max_ref_updates",
      parameters: {
        "max_ref_updates" => 1
      }
    )

    @configs_by_ref_update = ref_updates.each_with_object({}) do |ref_update, hash|
      hash[ref_update] = [@rule_config]
    end

    @rule = RuleEngine::Rules::MaxRefUpdatesRule.new
  end

  test "fails all rule runs if the number of ref updates exceeds the configured limit" do
    rule_runs = @rule.bulk_evaluate(@context, @configs_by_ref_update)

    assert_equal 2, rule_runs.size

    assert_predicate rule_runs[0], :failed?
    assert_predicate rule_runs[1], :failed?
  end

  test "allows all rule runs if the number of ref updates is less than the configured limit" do
    @rule_config.parameters["max_ref_updates"] = 2

    rule_runs = @rule.bulk_evaluate(@context, @configs_by_ref_update)

    assert_equal 2, rule_runs.size

    assert_predicate rule_runs[0], :allowed?
    assert_predicate rule_runs[1], :allowed?
  end

  test "handles when configured limit is less than zero" do
    @rule_config.parameters["max_ref_updates"] = -1

    rule_runs = @rule.bulk_evaluate(@context, @configs_by_ref_update)

    assert_equal 2, rule_runs.size

    assert_predicate rule_runs[0], :allowed?
    assert_predicate rule_runs[1], :allowed?
  end
end
