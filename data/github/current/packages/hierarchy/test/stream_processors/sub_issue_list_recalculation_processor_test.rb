# typed: true
# frozen_string_literal: true

require "test_helper"

class SubIssueListRecalculationProcessorTest < GitHub::TestCase
  include HydroTestHelpers
  include SubIssuesHelpers

  setup do
    @issues = create_hierarchy! <<~HIERARCHY
    - parent
      - child1
      - child2
      - child3
    HIERARCHY
    @parent = @issues["parent"]
    @repo = @issues["parent"]&.repository
    reset_hydro # clear messages from setup
  end

  test "recaulcuates sub-issue list for close message" do
    @issues["child1"].close
    message = {
      repository: Hydro::EntitySerializer.repository(@repo),
      issue: Hydro::EntitySerializer.issue(@issues["child1"])
    }
    hydro_publisher.publish(message, schema: "github.v1.IssueClose")
    run_processor(HierarchyProcessors::SubIssueListRecalculationProcessor.new, allowed_primary_query_count: 4)

    assert_equal 1, @parent.sub_issue_list.completed
    assert_equal 3, @parent.sub_issue_list.total
  end

  test "recaulcuates sub-issue list for reopen message" do
    @issues["child2"].close
    message = {
      repository: Hydro::EntitySerializer.repository(@repo),
      issue: Hydro::EntitySerializer.issue(@issues["child1"])
    }
    hydro_publisher.publish(message, schema: "github.v1.IssueReopen")
    run_processor(HierarchyProcessors::SubIssueListRecalculationProcessor.new, allowed_primary_query_count: 4)

    assert_equal 1, @parent.sub_issue_list.completed
    assert_equal 3, @parent.sub_issue_list.total
  end

  test "does nothing for an issue without a parent" do
    new_issue = create(:issue, repository: @repo)
    message = {
      repository: Hydro::EntitySerializer.repository(@repo),
      issue: Hydro::EntitySerializer.issue(new_issue)
    }
    hydro_publisher.publish(message, schema: "github.v1.IssueClose")
    assert_query_count_per_table({
      sub_issue_list: 0
    }) do
      run_processor(HierarchyProcessors::SubIssueListRecalculationProcessor.new, allowed_primary_query_count: 0)
    end
  end

  test "recaulcuates sub-issue list for add_sub_issue message" do
    @issues["child3"].close
    message = {
      source_issue: Hydro::EntitySerializer.issue(@parent)
    }
    hydro_publisher.publish(message, schema: "github.v1.SubIssueAdd")
    run_processor(HierarchyProcessors::SubIssueListRecalculationProcessor.new, allowed_primary_query_count: 4)

    assert_equal 1, @parent.sub_issue_list.completed
    assert_equal 3, @parent.sub_issue_list.total
  end

  test "recaulcuates sub-issue list for remove_sub_issue message" do
    @issues["child1"].close
    message = {
      source_issue: Hydro::EntitySerializer.issue(@parent)
    }
    hydro_publisher.publish(message, schema: "github.v1.SubIssueRemove")
    run_processor(HierarchyProcessors::SubIssueListRecalculationProcessor.new, allowed_primary_query_count: 4)

    assert_equal 1, @parent.sub_issue_list.completed
    assert_equal 3, @parent.sub_issue_list.total
  end
end
