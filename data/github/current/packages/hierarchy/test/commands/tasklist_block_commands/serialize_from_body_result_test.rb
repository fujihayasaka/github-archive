# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlockCommands::SerializeFromBodyResultTest < GitHub::TestCase
  # include GitHub::QueryAssertionTestHelpers


  fixtures do
    @repo = create(:repository)
    @labels = create_list(:label, 3, repository: @repo)
    @issue_one = create(:issue, repository: @repo, labels: [@labels.sample])
    @issue_two = create(:issue, repository: @repo, labels: [@labels.sample])
  end

  setup do
    @tasklist_block = TasklistBlocks::TasklistBlock.new(
      name: "Tasklist One",
      items: [
        TasklistBlocks::IssueReference.new(issue: @issue_one),
        TasklistBlocks::IssueReference.new(issue: @issue_two),
        TrackingBlocks::DraftIssue.new(
          draft_issue: "some draft",
          owner_id: @issue_one.user_id,
        )
      ]
    )
  end

  test "serializes a result" do
    result = klass.new(tasklists: @tasklist_block).call
    expected = [
      {
        name: @tasklist_block.name,
        issues: @tasklist_block.items.map(&:to_hierarchy_model)
      }
    ]
    assert_equal expected, result.data
  end

  test "handles multiple tasklists" do
    result = klass.new(tasklists: [@tasklist_block, @tasklist_block]).call
    expected = [
      {
        name: @tasklist_block.name,
        issues: @tasklist_block.items.map(&:to_hierarchy_model)
      },
      {
        name: @tasklist_block.name,
        issues: @tasklist_block.items.map(&:to_hierarchy_model)
      }
    ]
    assert_equal expected, result.data
  end

  test "prefills associations to eliminate N+1" do
    assert_max_query_count_per_table({
      assignments: 1,
      labels: 1,
      repositories: 1,
      issues_labels: 1,
    }) do
      klass.new(tasklists: @tasklist_block).call
    end
  end

  test "returns a success result" do
    result = klass.new(tasklists: @tasklist_block).call
    assert_predicate result, :success?
  end

  private

  def klass
    TasklistBlockCommands::SerializeFromBodyResult
  end
end
