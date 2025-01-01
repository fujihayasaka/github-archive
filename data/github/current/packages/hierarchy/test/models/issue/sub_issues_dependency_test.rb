# typed: true
# frozen_string_literal: true

require "test_helper"

class SubIssuesDependencyTest < GitHub::TestCase
  include SubIssuesHelpers
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @user = create(:user)
    repository = create(:private_repository, owner: @user)
    @parent = create(:issue, repository:, user: @user)
    @parent2 = create(:issue, repository:, user: @user)
    @child1 = create(:issue, repository:, user: @user)
    @child2 = create(:issue, repository:, user: @user)

    @user.enable_feature(:sub_issues)
  end

  context "add_sub_issue!" do
    test "add issue to bottom by default" do
      @parent.add_sub_issue!(@child1, @user.id)

      assert_equal @child1, @parent.prioritized_sub_issues.first

      @parent.add_sub_issue!(@child2, @user.id)
      assert_equal @child2, @parent.prioritized_sub_issues.last
    end

    test "add issue to top when specified" do
      @parent.add_sub_issue!(@child1, @user.id)

      assert_equal @child1, @parent.prioritized_sub_issues.first

      @parent.add_sub_issue!(@child2, @user.id, position: :top)
      assert_equal @child2, @parent.prioritized_sub_issues.first
    end
  end

  context "add_or_replace_parent!" do
    test "adds issue as sub-issue to parent" do
      @child1.add_or_replace_parent!(@parent, @user)
      assert_equal @child1, @parent.prioritized_sub_issues.first

      @child2.add_or_replace_parent!(@parent.reload, @user)
      assert_equal @child2, @parent.reload.prioritized_sub_issues.last
    end

    test "adds issue with a parent as sub-issue to new parent" do
      @child1.add_or_replace_parent!(@parent, @user)
      assert_equal @child1, @parent.prioritized_sub_issues.first

      @parent.recalculate_sub_issue_list!
      assert_equal 1, @parent.sub_issue_list.total

      @child1.reload.add_or_replace_parent!(@parent2, @user)
      assert_equal @child1, @parent2.prioritized_sub_issues.first

      @parent.reload.recalculate_sub_issue_list!
      assert_equal 0, @parent.sub_issue_list.total
    end

    test "throws a validation error when the hierarchy height " do
      unable_to_add_child = create(:issue, title: "unable to add child", repository: @parent.repository)
      issues = create_hierarchy!("
      - parent
        - child 1
          - child 2
            - child 3
              - child 4
                - child 5
                  - child 6
                    - child 7
      ", repository: @parent.repository)

      assert_equal 7, issues["parent"]&.sub_issue_list&.height
      heights = issues.transform_values { |issue| issue.reload.sub_issue_list&.height }
      expected_heights = {
        "parent" => 7,
        "child 1" => 6,
        "child 2" => 5,
        "child 3" => 4,
        "child 4" => 3,
        "child 5" => 2,
        "child 6" => 1,
        "child 7" => nil,
      }
      assert_equal expected_heights, heights

      assert_raises_with_message(StandardError, "You can’t add more than 7 layers of sub-issues. To add a sub-issue, remove a parent issue at any level.") do
        T.must(issues["parent"]).add_or_replace_parent!(unable_to_add_child, @user)
      end
    end
  end

  context "async_filtered_prioritized_sub_issues" do
    test "returns prioritized issues" do
      @parent.add_sub_issue!(@child1, @user.id)
      @parent.add_sub_issue!(@child2, @user.id, position: :top)
      sub_issues = @parent.async_filtered_prioritized_sub_issues(viewer: @user, cap_filter: cap_authorizing_filter).sync
      assert_equal @child2, sub_issues.first
      assert_equal @child1, sub_issues.second
    end

    test "filters out inaccessible issues" do
      @parent.add_sub_issue!(@child1, @user.id)
      @child2.stubs(:async_hide_from_user?).returns(true)
      @parent.add_sub_issue!(@child2, @user.id)

      sub_issues = @parent.async_filtered_prioritized_sub_issues(viewer: @user, cap_filter: cap_authorizing_filter(@child1)).sync
      assert_equal 1, sub_issues.length
      assert_equal @child1.title, sub_issues.first.title
    end

    test "filters out spammy issues" do
      spammy_user = create(:user, spammy: true)
      spammy_issue = create(:issue, repository: @parent.repository, user: spammy_user)
      @parent.add_sub_issue!(@child1, @user.id)
      @parent.add_sub_issue!(spammy_issue, @user.id)

      sub_issues = @parent.async_filtered_prioritized_sub_issues(viewer: @user, cap_filter: cap_authorizing_filter).sync
      assert_equal 1, sub_issues.length
      assert_equal @child1.title, sub_issues.first.title
    end if GitHub.spamminess_check_enabled?

    # regression test for https://github.com/github/sub-issues/issues/153
    test "filters out nil issues" do
      @parent.add_sub_issue!(@child1, @user.id)
      # delete will destroy child without triggering callbacks, which would clean-up the sub-issue relation normally
      @child1.delete

      # There should be 1 sub-issue relation, but the sub-issue should be nil
      assert_equal 1, @parent.sub_issue_relations.count
      assert_nil @parent.sub_issue_relations.first.target

      # The sub-issue should be filtered out, just to be safe
      sub_issues = @parent.async_filtered_prioritized_sub_issues(viewer: @user, cap_filter: cap_authorizing_filter).sync
      assert_equal 0, sub_issues.length
    end
  end

  context "async_sub_issues_summary" do
    test "should be able to get total and completion counts for sub-issues" do
      @parent.add_sub_issue!(@child1, @user.id)
      @parent.add_sub_issue!(@child2, @user.id)
      @parent.recalculate_sub_issue_list!

      completion = @parent.async_sub_issues_summary.sync
      assert_equal 2, completion[:total]
      assert_equal 0, completion[:completed]
      assert_equal 0, completion[:percent_completed]

      @child2.update!(state: :closed)
      @parent.reload
      @parent.recalculate_sub_issue_list!

      completion = @parent.async_sub_issues_summary.sync
      assert_equal 2, completion[:total]
      assert_equal 1, completion[:completed]
      assert_equal 50, completion[:percent_completed]
    end

    test "should only query the list, and no other tables when available" do
      @parent.add_sub_issue!(@child1, @user.id)
      @parent.add_sub_issue!(@child2, @user.id)
      @child2.update!(state: :closed)
      @parent.recalculate_sub_issue_list!

      reloaded_parent = Issue.find(@parent.id)
      assert_query_count_per_table({
        issues: 0,
        sub_issues: 0,
        sub_issue_lists: 1,
      }) do
        completion = reloaded_parent.async_sub_issues_summary.sync
        assert_equal 2, completion[:total]
        assert_equal 1, completion[:completed]
        assert_equal 50, completion[:percent_completed]
      end
    end

    test "should use the sub_issue_list if available" do
      @parent.add_sub_issue!(@child1, @user.id)
      @parent.add_sub_issue!(@child2, @user.id)
      @child2.update!(state: :closed)

      @parent.recalculate_sub_issue_list!
      completion = @parent.async_sub_issues_summary.sync
      assert_equal 2, completion[:total]
      assert_equal 1, completion[:completed]
      assert_equal 50, completion[:percent_completed]
    end

    test "shouldn't use sub_issue_list if calculated is true" do
      @parent.add_sub_issue!(@child1, @user.id)
      @parent.add_sub_issue!(@child2, @user.id)
      @child2.update!(state: :closed)

      @parent.recalculate_sub_issue_list!
      SubIssueList.any_instance.expects(:total).never
      SubIssueList.any_instance.expects(:completed).never
      completion = @parent.async_sub_issues_summary(calculate: true).sync
      assert_equal 2, completion[:total]
      assert_equal 1, completion[:completed]
      assert_equal 50, completion[:percent_completed]
    end
  end

  context "recalculate_sub_issue_list!" do
    test "should create new sub-issue list if none exists" do
      @parent.add_sub_issue!(@child1, @user.id)
      @child2.update!(state: :closed)
      @parent.add_sub_issue!(@child2, @user.id)
      @parent.recalculate_sub_issue_list!

      assert_equal 2, @parent.sub_issue_list.total
      assert_equal 1, @parent.sub_issue_list.completed
    end

    test "should update existing sub-issue list if one exists" do
      @parent.add_sub_issue!(@child1, @user.id)
      @parent.recalculate_sub_issue_list!
      assert_equal 1, @parent.sub_issue_list.total
      assert_equal 0, @parent.sub_issue_list.completed

      @child2.update!(state: :closed)
      @parent.add_sub_issue!(@child2, @user.id)
      @parent.reload
      @parent.recalculate_sub_issue_list!
      assert_equal 2, @parent.sub_issue_list.total
      assert_equal 1, @parent.sub_issue_list.completed
    end
  end
end
