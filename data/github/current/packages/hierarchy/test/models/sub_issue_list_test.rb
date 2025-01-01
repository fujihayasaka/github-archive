# typed: true
# frozen_string_literal: true

require "test_helper"

class SubIssueListTest < GitHub::TestCase
  include PrioritizationHelpers

  fixtures do
    repo = create(:repository)
    @parent = create(:issue, repository: repo)
    @child1 = create(:issue, title: "child 1", repository: repo)
    @child2 = create(:issue, title: "child 2", repository: repo, state: "closed")
    @user = create(:user)
    @parent.add_sub_issue!(@child1, @user.id)
    @parent.add_sub_issue!(@child2, @user.id)
  end

  context "recalculate!" do
    test "should be able to recalculate list" do
      sub_issue_list = @parent.recalculate_sub_issue_list!

      assert_equal 2, sub_issue_list.total
      assert_equal 1, sub_issue_list.completed
      assert_equal 50, sub_issue_list.percent_completed

      @child1.update!(state: :closed)
      sub_issue_list.reload
      assert_query_count_per_table({
        # 1 query for the parent, then 1 query for all of the sub-issues
        issues: 2,
        sub_issue_lists: 1
      }) do
        sub_issue_list.recalculate!
      end

      assert_equal 2, sub_issue_list.total
      assert_equal 2, sub_issue_list.completed
      assert_equal 100, sub_issue_list.percent_completed
    end
  end

  context "#to_h" do
    test "should return a proper hash" do
      sub_issue_list = @parent.recalculate_sub_issue_list!

      assert_equal({ total: 2, completed: 1, percent_completed: 50 }, sub_issue_list.to_h)
    end
  end

  context "#csv_column_value" do
    test "should return a proper value" do
      sub_issue_list = @parent.recalculate_sub_issue_list!

      assert_equal "#{sub_issue_list.percent_completed}%", sub_issue_list.csv_column_value
    end
  end
end
