# typed: true
# frozen_string_literal: true
require "test_helper"

class IssueCommentOrchestrationJobTest < GitHub::TestCase
  test "issue_comment_orchestration queue is used" do
    assert_enqueued_jobs 1, only: IssueCommentOrchestrationJob, queue: :issue_comment_orchestration do
      IssueCommentOrchestrationJob.perform_later(1, "CreateIssueCommentOrchestration")
    end
  end
end
