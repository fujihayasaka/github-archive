# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RebalanceMilestoneJobTest < GitHub::TestCase
  include JobTestHelper
  include PrioritizationHelpers

  fixtures do
    @milestone = create :milestone
    @repo = @milestone.repository
    @user = @repo.owner
  end

  test "doesn't do anything if the milestone doesn't exist" do
    refute RebalanceMilestoneJob.perform_now(-1, 1)
  end

  test "rebalances a milestone" do
    issue_priorities = []

    3.downto(1) do |i|
      issue_priorities << create(:issue_priority, milestone: @milestone, priority: i)
    end

    @milestone.reload
    assert_equal issue_priorities, @milestone.issue_priorities.by_priority

    # Ensure priorities are sequential
    @milestone.issue_priorities.by_priority.each_with_index do |issue_priority, i|
      if next_issue_priority = @milestone.issue_priorities.by_priority[i + 1]
        assert_equal issue_priority.priority, next_issue_priority.priority + 1
      end
    end

    RebalanceMilestoneJob.perform_now(@milestone.id, @user.id)
    @milestone.reload

    # Make sure the issue priorities are still in the right order
    assert_equal issue_priorities, @milestone.issue_priorities.by_priority

    # Ensure priorities are no longer sequential
    @milestone.issue_priorities.by_priority.each_with_index do |issue_priority, i|
      if next_issue_priority = @milestone.issue_priorities.by_priority[i + 1]
        assert_operator issue_priority.priority, :>, next_issue_priority.priority + 1
      end
    end
  end

  test "doesn't cause a collision after an issue is moved" do
    issue_priority_c = create(:issue_priority, milestone: @milestone)
    issue_priority_b = create(:issue_priority, milestone: @milestone)
    issue_priority_a = create(:issue_priority, milestone: @milestone)

    assert_equal [issue_priority_a, issue_priority_b, issue_priority_c], @milestone.issue_priorities.by_priority

    allow_transaction_nesting do
      @milestone.prioritize_issue!(issue_priority_a.issue, after: issue_priority_c.issue)
      RebalanceMilestoneJob.perform_now(@milestone.id, @user.id)

      [issue_priority_a, issue_priority_b, issue_priority_c].each(&:reload)

      @milestone.prioritize_issue!(issue_priority_b.issue, after: issue_priority_a.issue)
      RebalanceMilestoneJob.perform_now(@milestone.id, @user.id)
    end

    @milestone.reload

    assert_equal [issue_priority_c, issue_priority_a, issue_priority_b], @milestone.issue_priorities.by_priority
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: RebalanceMilestoneJob, args: [@milestone.id, @user.id]
  end
end
