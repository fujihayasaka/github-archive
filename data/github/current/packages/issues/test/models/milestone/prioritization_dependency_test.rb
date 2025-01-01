# typed: true
# frozen_string_literal: true

require "test_helper"

class MilestonePrioritizationTest < GitHub::TestCase
  include PrioritizationHelpers

  fixtures do
    @owner     = create :user, login: "owner", plan: "large"
    @repo      = create :private_repository, owner: @owner

    @milestone = create(:milestone, title: "The Great Release", repository: @repo)

    1.upto(5).each do |nth|
      instance_variable_set :"@issue#{nth}",
        create(:issue,
          repository: @repo,
          user: @owner,
          milestone: @milestone,
          title: "Issue #{nth}",
        )
    end
  end

  setup do
    # This is necessary for JobStatus to work
    GitHub.cache.allow = /.*/
    GitHub.cache.clear
  end

  teardown do
    GitHub.cache.clear
  end

  context "#prioritizable?" do
    test "is true when backfilling is needed" do
      @milestone.stubs(:needs_backfill?).returns(true)
      assert_predicate @milestone, :prioritizable?
    end

    test "is true when open issue count is less than MAXIMUM_PRIORITIZABLE_ITEM_COUNT" do
      assert @milestone.open_issue_count < GitHub::Prioritizable::MAXIMUM_PRIORITIZABLE_ITEM_COUNT
      assert_predicate @milestone, :prioritizable?
    end

    test "is false when open issue count is at or exceeds MAXIMUM_PRIORITIZABLE_ITEM_COUNT" do
      GitHub::Prioritizable.stub_const(:MAXIMUM_PRIORITIZABLE_ITEM_COUNT, 1) do
        create(:issue_priority, milestone: @milestone)
        create(:issue_priority, milestone: @milestone)

        refute_predicate @milestone, :prioritizable?

        assert @milestone.open_issue_count > GitHub::Prioritizable::MAXIMUM_PRIORITIZABLE_ITEM_COUNT
      end
    end
  end

  context "#prioritized_issues" do
    test "returns the list of open issues (most recent first) when milestone hasn't been prioritized" do
      @issue1.close
      @milestone.issue_priorities.destroy_all
      assert @issue5.created_at >= @issue1.created_at
      assert_equal [@issue5, @issue4, @issue3, @issue2], @milestone.prioritized_issues
    end

    test "returns the list of open issues in (reverse) priority order when milestone has been prioritized" do
      @issue1.close
      assert_equal [@issue2, @issue3, @issue4, @issue5], @milestone.prioritized_issues
    end
  end

  context "#backfill!" do
    test "returns the number of issue_priorities created" do
      assert_equal @milestone.issues.count, @milestone.backfill!(force: true)
    end

    test "handles empty milestones with aplomb" do
      milestone = create :milestone
      assert_equal 0, milestone.issues.size
      milestone.backfill! # This shouldn't raise
    end

    test "only prioritizes open issues" do
      @issue1.close
      @milestone.backfill!(force: true)
      refute_includes @milestone.issue_priorities.reload.map(&:issue), @issue1
    end

    context "when already prioritized" do
      test "does nothing" do
        refute @milestone.backfill!
      end

      test "clears the existing priorities and starts over with force: true" do
        old_priority_ids = @milestone.issue_priorities.pluck(:id)
        @milestone.backfill!(force: true)
        refute_predicate IssuePriority.where(id: old_priority_ids), :exists?
        assert_equal @milestone.issues.count, @milestone.issue_priorities.reload.count
      end
    end

    context "when nothing has been prioritized yet" do
      test "creates an issue_priority for each of the associated issues" do
        @milestone.issue_priorities.destroy_all

        assert_difference("IssuePriority.count", @milestone.issues.size) do
          @milestone.backfill!(force: true)
        end
      end
    end
  end

  context "#prioritized_issues" do
    test "returns all issues in priority order" do
      assert_equal [@issue1, @issue2, @issue3, @issue4, @issue5], @milestone.prioritized_issues.all
    end

    test "still works after reprioritizing" do
      @milestone.prioritize_issue!(@issue5, before: @issue1)
      assert_equal [@issue5, @issue1, @issue2, @issue3, @issue4], @milestone.prioritized_issues.all
    end
  end

  context "adding an issue to a milestone" do
    test "prioritizes the issue" do
      assert_difference("@milestone.issue_priorities.count") do
        create :issue, repository: @repo, user: @owner, milestone: @milestone
      end
    end
  end

  context "#prioritized_issues" do
    test "works" do
      assert_equal 5, @milestone.prioritized_issues.size
    end
  end

  context "#deprioritize_dependent" do
    context "when you're over the limit" do
      test "deprioritize still works" do
        @milestone.stubs(:prioritizable?).returns(false)

        assert_difference("IssuePriority.count", -1) do
          @milestone.deprioritize_dependent(@issue1)
        end
        assert_empty @issue1.issue_priorities
      end
    end

    test "silently ignores an issue that isn't prioritized currently" do
      assert_no_difference("@milestone.issue_priorities.count") do
        @milestone.deprioritize_dependent(create :issue, repository: @repo)
      end
    end

    test "removes the corresponding IssuePriority" do
      @issue1.update_column(:milestone_id, nil) # don't run callbacks
      assert_difference("@milestone.issue_priorities.count", -1) do
        @milestone.deprioritize_dependent(@issue1)
      end
    end
  end

  context "issue changes milestone" do
    test "removes priority from the old milestone, adds priority to the new milestone" do
      old_priority  = @issue1.issue_priorities.first
      new_milestone = create(:milestone, repository: @repo)
      @issue1.milestone = new_milestone
      @issue1.save!

      new_priority = @issue1.issue_priorities.first
      refute_equal old_priority, new_priority
      assert_equal 1, new_priority.canonical_priority
      assert_equal new_milestone, new_priority.milestone
    end
  end

  context "issues are closed and reopened" do
    test "does not disturb the prioritization of other open issues" do
      allow_transaction_nesting { @issue1.close }

      assert_equal [@issue2, @issue3, @issue4, @issue5],
        @milestone.prioritized_issues

      allow_transaction_nesting do
        @milestone.prioritize_issue!(@issue5, before: @issue3)
      end

      assert_equal [@issue2, @issue5, @issue3, @issue4],
        @milestone.prioritized_issues

      allow_transaction_nesting { @issue4.close }

      assert_equal [@issue2, @issue5, @issue3],
        @milestone.prioritized_issues

      allow_transaction_nesting { assert @issue1.reopen! }

      assert_equal [@issue1, @issue2, @issue5, @issue3],
        @milestone.prioritized_issues
    end
  end

  context "#prioritize_issue!" do
    test "returns when the milestone needs backfill" do
      @milestone.stubs(:needs_backfill?).returns(true)
      new_issue = create(:issue, repository: @repo)

      assert_no_difference("IssuePriority.count") do
        refute @milestone.prioritize_issue!(new_issue)
      end

      assert_empty new_issue.issue_priorities
    end

    test "cannot prioritize a closed issue" do
      closed_issue = create(:issue, repository: @repo, state: "closed")
      # prevent automatic prioritization
      closed_issue.update_column(:milestone_id, @milestone.id)
      refute @milestone.prioritize_issue!(closed_issue)
    end

    context "without before: or after: specified" do
      test "can prioritize an unprioritized issue" do
        new_issue = create(:issue, repository: @repo)
        new_issue.update_column(:milestone_id, @milestone.id)
        @milestone.prioritize_issue!(new_issue)
        assert_equal 1, new_issue.issue_priorities.first.canonical_priority
      end

      test "moves a prioritized issue to the top" do
        assert_equal 4, @issue4.issue_priorities.first.canonical_priority
        @milestone.prioritize_issue!(@issue4)
        assert_equal 1, @issue4.issue_priorities.first.canonical_priority
      end

      test "moves a prioritized issue to the bottom" do
        assert_equal 1, @issue1.issue_priorities.first.canonical_priority
        @milestone.prioritize_issue!(@issue1, position: :bottom)
        assert_equal 5, @issue1.issue_priorities.last.canonical_priority
      end
    end

    context "with before" do
      test "can move an issue up in the list" do
        assert_equal 5, @issue5.issue_priorities.first.canonical_priority
        @milestone.prioritize_issue!(@issue5, before: @issue1)
        assert_equal 1, @issue5.issue_priorities.first.canonical_priority
      end

      test "can move an issue down in the list" do
        assert_equal 1, @issue1.issue_priorities.first.canonical_priority
        @milestone.prioritize_issue!(@issue1, before: @issue5)
        assert_equal 4, @issue1.issue_priorities.first.canonical_priority
      end
    end

    context "with after" do
      test "can move an issue up in the list" do
        assert_equal 5, @issue5.issue_priorities.first.canonical_priority
        @milestone.prioritize_issue!(@issue5, after: @issue1)
        assert_equal 2, @issue5.issue_priorities.first.canonical_priority
      end

      test "can move an issue down in the list" do
        assert_equal 1, @issue1.issue_priorities.first.canonical_priority
        allow_transaction_nesting do
          @milestone.prioritize_issue!(@issue1, after: @issue5)
        end
        assert_equal 5, @issue1.issue_priorities.first.canonical_priority
      end
    end
  end
end
