# typed: true
# frozen_string_literal: true

require "test_helper"

class MergeConditions::EvaluatorTest < GitHub::TestCase
  # NOTE: Each condition is tested more thoroughly in its own test file.
  # This test is intended to confirm the evaluator does its job

  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
    @pull = create(:pull_request, :with_mergeable_head, repository: @repo)
  end

  test "evaluator returns one condition for each registered condition" do
    registered_conditions = MergeConditions::Evaluator::CONDITIONS

    merge_conditions = MergeConditions::Evaluator.async_evaluate(@pull, @owner, :merge, skip_checks: false).sync

    assert_equal registered_conditions.count, merge_conditions.count
    merge_conditions.each do |result|
      assert result.is_a?(MergeConditions::BaseMergeCondition)
    end
  end
end
