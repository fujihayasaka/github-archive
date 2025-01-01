# typed: true
# frozen_string_literal: true
require "test_helper"

class PullRequestOrchestrationJobTest < GitHub::TestCase
  test "pull_request_orchestration queue is used" do
    assert_enqueued_jobs 1, only: PullRequestOrchestrationJob, queue: :pull_request_orchestration do
      PullRequestOrchestrationJob.perform_later(1, "PullRequestReviewCommentOrchestration")
    end
  end
end
