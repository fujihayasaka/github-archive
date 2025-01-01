# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEngineMaxFileSizeRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include RulesEngine::CandidateTestHelper

  fixtures do
    @repo = create(:repository)
  end

  setup do
    @context = RuleEngine::RuleEvaluationContext.new(@repo)
    @ref_update = create_branch_update(@repo)

    @rule_config = build(
      :repository_rule_configuration,
      rule_type: "max_file_size_rule",
      parameters: {
        "max_file_size" => 5
      }
    )

    @rule = T::let(RuleEngine::Rules::MaxFileSizeRule.new, RuleEngine::Rules::MaxFileSizeRule)
  end

  test "succeeds when path within limit" do
    candidate = create_blob_candidate(size: convert_to_bytes(5))
    result = @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate)

    assert result.success?
  end

  test "fails when path exceeds limit" do
    candidate = create_blob_candidate(size: convert_to_bytes(10))
    result = @rule.evaluate_candidate(@context, @ref_update, @rule_config, candidate)

    refute result.success?
  end

  test "generates allowed rule run when no violations" do
    result = @rule.generate_evaluation_result(@context, @ref_update, @rule_config, [])

    assert_predicate result, :allowed?
  end

  test "generates failed rule run when violations exist" do
    violations = [RuleEngine::Violation.new(candidate: create_blob_candidate(size: convert_to_bytes(10)))]

    result = @rule.generate_evaluation_result(@context, @ref_update, @rule_config, violations)

    assert_predicate result, :failed?
  end

  private

  def convert_to_bytes(size_in_mb)
    size_in_mb * 1024 * 1024
  end
end
