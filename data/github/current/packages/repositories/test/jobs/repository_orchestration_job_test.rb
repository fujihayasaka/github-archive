# typed: strict
# frozen_string_literal: true
require "test_helper"

class RepositoryOrchestrationJobTest < GitHub::TestCase
  test "repository_orchestration queue is used" do
    assert_enqueued_jobs 1, only: RepositoryOrchestrationJob, queue: :repository_orchestration do
      RepositoryOrchestrationJob.perform_later(1, "CreateRepositoryOrchestration")
    end
  end
end
