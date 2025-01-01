# typed: true
# frozen_string_literal: true

require "test_helper"

module TasklistBlocks
  class IssueReferenceTest < GitHub::TestCase
    fixtures do
      @issue = create(:issue)
    end

    test "equality" do
      issue = TasklistBlocks::IssueReference.new(issue: @issue)
      other = TasklistBlocks::IssueReference.new(issue: @issue)

      assert_equal issue, other
    end

    test "equality with different issues" do
      other_issue = create(:issue)
      issue = TasklistBlocks::IssueReference.new(issue: @issue)
      other = TasklistBlocks::IssueReference.new(issue: other_issue)

      refute_equal issue, other
    end

    test "#draft?" do
      refute_predicate TasklistBlocks::IssueReference.new(issue: @issue), :draft?
    end

    test "to_hierarchy_model gets the hierarchy model for a pull_request if an issue is part of a PR / Issue pair" do
      issue_two = create(:issue)
      GitHub.flipper[:tasklist_block].enable(issue_two.owner)
      pull_request = create(:pull_request, :merged, :disable_disk_access, issue: issue_two, repository: issue_two.repository)
      issue_two.reload
      issue_reference = TasklistBlocks::IssueReference.new(issue: issue_two)

      expected = pull_request.to_hierarchy_model.merge(position: nil)

      assert_equal issue_reference.to_hierarchy_model, expected
    end

    test "to_hierarchy_model works on an issue" do
      issue_reference = TasklistBlocks::IssueReference.new(issue: @issue)

      expected = @issue.to_hierarchy_model.merge(position: nil)

      assert_equal issue_reference.to_hierarchy_model, expected
    end
  end
end
