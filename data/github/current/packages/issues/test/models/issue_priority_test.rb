# typed: true
# frozen_string_literal: true

require "test_helper"

class IssuePriorityTest < GitHub::TestCase
  include PrioritizationHelpers

  fixtures do
    @repo      = create(:repository)
    @milestone = create(:milestone, title: "Great Feature", repository: @repo)

    without_gaps do
      @issue3    = create(:issue, repository: @repo, milestone: @milestone)
      @issue2    = create(:issue, repository: @repo, milestone: @milestone)
      @issue1    = create(:issue, repository: @repo, milestone: @milestone)
    end

    @priority1 = @issue1.issue_priorities.first
    @priority2 = @issue2.issue_priorities.first
    @priority3 = @issue3.issue_priorities.first

    @priority2.reprioritize(after: @priority1)
    @priority3.reprioritize(after: @priority2)
  end

  context "when a collision happens in the database" do
    test "we push to Datadog and add a validation error" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @priority3.stubs(:insert_before).raises(ActiveRecord::RecordNotUnique.new(:a))

      assert_difference -> { GitHub.dogstats.increments("issue_priority.prioritization.error.record_not_unique").length } do
        @priority3.reprioritize(before: @issue1)
        assert @priority3.errors[:prioritization].any?
      end
    end
  end

  context "#siblings" do
    test "returns all other issue priorities in the milestone" do
      assert_same_elements @priority1.siblings, [@priority2, @priority3]
      assert_same_elements @priority2.siblings, [@priority1, @priority3]
      assert_same_elements @priority3.siblings, [@priority1, @priority2]
    end
  end

  context "#reprioritize without before or after" do
    test "results in the issue being the first priority in the milestone" do
      @priority3.reprioritize
      assert_equal [@issue3, @issue1, @issue2], @milestone.prioritized_issues
    end

    test "results in the issue being the last priority when specified" do
      @priority1.reprioritize(position: :bottom)
      assert_equal [@issue2, @issue3, @issue1], @milestone.prioritized_issues
    end

    # See https://github.com/github/github/issues/126769
    test "rebalances priorities if new priority would be out of bounds" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      assert_difference -> { GitHub.dogstats.increments("issue_priority.prioritization.rebalance.priority_out_of_range").length } do
        @priority3.update(priority: 1)
        @priority1.reprioritize(position: :bottom)
        assert_equal [@issue2, @issue3, @issue1], @milestone.prioritized_issues
      end
    end

    # See https://github.com/github/github/issues/126769
    test "safely inserts record at bottom even if lowest priority would be out of bounds" do
      assert_equal [@issue1, @issue2, @issue3], @milestone.prioritized_issues

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      assert_difference -> { GitHub.dogstats.increments("issue_priority.prioritization.rebalance.priority_out_of_range").length } do
        @priority3.update(priority: 1)

        new_issue = create(:issue, repository: @repo, milestone: @milestone)
        assert_equal [@issue1, @issue2, @issue3, new_issue], @milestone.prioritized_issues
      end
    end

    test "leaves gaps, and we're okay with that" do
      former_priority = @priority2.priority
      @priority2.reprioritize
      refute_predicate @milestone.issue_priorities.where(priority: former_priority), :exists?
    end
  end

  context "#reprioritize with before" do
    test "can move priorities up" do
      allow_transaction_nesting do
        @priority3.reprioritize(before: @issue1)
        assert_equal [@issue3, @issue1, @issue2], @milestone.prioritized_issues
      end
    end

    test "can move priorities down" do
      allow_transaction_nesting do
        @priority1.reprioritize(before: @issue3)
        assert_equal [@issue2, @issue1, @issue3], @milestone.prioritized_issues
      end
    end

    test "can move no more than MAX_MOVES positions away-attempting to do so will trigger a rebalance" do
      GitHub::Prioritizable.stub_const(:MAX_MOVES, 5) do
        milestone = create :milestone
        (GitHub::Prioritizable::MAX_MOVES + 3).times { create(:issue_priority, milestone: milestone) }
        lowest_priority = milestone.issue_priorities.by_priority.last
        highest_priority = milestone.issue_priorities.by_priority.first

        assert_enqueued_jobs 1, only: RebalanceMilestoneJob do
          assert_raises(GitHub::Prioritizable::RebalanceRequiredError) do
            allow_transaction_nesting do
              highest_priority.reprioritize(before: lowest_priority.issue)
            end
          end
        end
      end
    end

    test "can move more than MAX_MOVES positions away if moving to the top of the list" do
      GitHub::Prioritizable.stub_const(:MAX_MOVES, 5) do
        milestone = create :milestone
        (GitHub::Prioritizable::MAX_MOVES + 3).times { create(:issue_priority, milestone: milestone) }
        lowest_priority = milestone.issue_priorities.by_priority.last
        highest_priority = milestone.issue_priorities.by_priority.first

        sibling_priorities_before = lowest_priority.siblings.by_priority.pluck(:priority)

        lowest_priority.reprioritize(before: highest_priority.issue)
        sibling_priorities_after = lowest_priority.siblings.by_priority.pluck(:priority)

        assert_equal sibling_priorities_before, sibling_priorities_after
      end
    end

    test "reprioritizing only priority is a no-op" do
      priority = create(:issue_priority)
      assert_no_difference("priority.priority") do
        priority.reprioritize
      end
    end
  end

  context "#reprioritize with after" do
    test "can move priorities up" do
      allow_transaction_nesting do
        @priority3.reprioritize(after: @issue1)
        assert_equal [@issue1, @issue3, @issue2], @milestone.prioritized_issues
      end
    end

    test "can move priorities down" do
      allow_transaction_nesting do
        @priority1.reprioritize(after: @issue3)
        assert_equal [@issue2, @issue3, @issue1], @milestone.prioritized_issues
      end
    end
  end

  context "#reprioritize with conflicting prioritization arguments" do
    test "can move priorities up" do
      allow_transaction_nesting do
        assert_raises GitHub::Prioritizable::ConflictingPrioritizationArgumentError do
          @priority3.reprioritize(after: @issue1, before: @issue2)
        end
      end
    end
  end

  test "#canonical_priority returns the logical position in the list" do
    assert_equal 1, @priority1.canonical_priority
    assert_equal 2, @priority2.canonical_priority
    assert_equal 3, @priority3.canonical_priority
  end

  test "updates the parent issue and milestone when prioritized" do
    @issue1.update_column(:updated_at, 5.days.ago)
    @milestone.update_column(:updated_at, 3.days.ago)

    allow_transaction_nesting do
      @milestone.prioritize_issue!(@issue1, before: @issue3)
    end

    assert_in_delta 0.days.ago, @issue1.reload.updated_at, 1.minute
    assert_in_delta 0.days.ago, @milestone.reload.updated_at, 1.minute
  end

  test "priority is only valid for the range of an unsigned BIGINT" do
    @priority1.priority = -1
    @priority2.priority = GitHub::Prioritizable::MAX_PRIORITY_VALUE + 1

    refute_predicate @priority1, :valid?
    refute_predicate @priority2, :valid?
  end

  test "invalid if issue is missing" do
    @priority1.issue = nil
    refute_predicate @priority1, :valid?
  end

  test "invalid if milestone is missing" do
    @priority1.milestone = nil
    refute_predicate @priority1, :valid?
  end

  test "cannot reprioritize inside nested transaction" do
    skip if GitHub.enterprise?
    assert_raises(GitHub::Prioritizable::CannotReprioritizeInNestedTransactionError) do
      Issue.transaction do
        @issue2.update_attribute(:title, "Birds")
        @priority3.reprioritize(before: @issue2)
      end
    end
  end

  test "sets `repository_id` from the issue" do
    issue_priority = create(:issue_priority)

    refute_nil issue_priority.repository_id
    assert_equal issue_priority.repository_id, issue_priority.issue.repository_id
  end
end
