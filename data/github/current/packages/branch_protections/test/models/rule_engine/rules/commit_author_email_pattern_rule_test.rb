# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEnginePushesCommitAuthorEmailPatternRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include RulesEngine::CandidateTestHelper

  fixtures do
    @repo = create(:repository)
  end

  setup do
    @context = RuleEngine::RuleEvaluationContext.new(@repo)
    @ref_update = create_branch_update(@repo)
    @rule = T::let(RuleEngine::Rules::CommitAuthorEmailPatternRule.new, RuleEngine::Rules::CommitAuthorEmailPatternRule)
  end

  test "sets appropriate property name, description, and value" do
    assert_equal "author.email", @rule.property_name
    assert_equal "Author email", @rule.property_description
    assert_equal "monalisa@github.com", @rule.property_value(create_commit_candidate)
  end

  test "only supports commit metadata" do
    assert_equal @rule.supported_metadata_types, [:commit]
  end

  test "skips evaluation when candidate is head commit when evaluating from merge box" do
    context = RuleEngine::RuleEvaluationContext.new(@repo, additional_context: { merge_box_evaluation: true })
    rule_config = create_rule_config("test", "regex")
    candidate = create_commit_candidate(id: @ref_update.after_oid)

    assert @rule.evaluate_candidate(context, @ref_update, @rule_config, candidate).success?
  end

  test "runs evaluation for pattern" do
    rule_config = create_rule_config("@github\.com$", "regex")
    passing_candidate = create_commit_candidate

    assert @rule.evaluate_candidate(@context, @ref_update, @rule_config, passing_candidate).success?

    failing_candidate = create_commit_candidate(author_email: "collaborator@microsoft.com")
    refute @rule.evaluate_candidate(@context, @ref_update, @rule_config, failing_candidate).success?
  end

  private

  def create_rule_config(pattern, operator, negate: false)
    @rule_config = build(
      :repository_rule_configuration,
      rule_type: "commit_author_email_pattern",
      parameters: {
        pattern: pattern,
        operator: operator,
        negate: negate
      }
    )
  end
end
