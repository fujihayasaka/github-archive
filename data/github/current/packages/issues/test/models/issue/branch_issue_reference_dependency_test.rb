# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueBranchIssueReferenceDependencyTest < GitHub::TestCase
  test "deletes BranchIssueReference when destroyed" do
    ref = create(:branch_issue_reference)

    assert_difference("BranchIssueReference.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { ref.issue.destroy }
    end

    refute BranchIssueReference.exists?(ref.id)
  end
end
