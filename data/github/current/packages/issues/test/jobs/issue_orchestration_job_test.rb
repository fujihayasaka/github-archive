# typed: true
# frozen_string_literal: true
require "test_helper"

class IssueOrchestrationJobTest < GitHub::TestCase
  test "issue_orchestration queue is used" do
    assert_enqueued_jobs 1, only: IssueOrchestrationJob, queue: :issue_orchestration do
      IssueOrchestrationJob.perform_later(1, "CreateIssueOrchestration")
    end
  end
end
