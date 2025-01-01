# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SimpleTestRepositoryOrchestration < RepositoryOrchestration
  step :step_1 do
  end

  job_start

  step :step_2 do
    if data[:raise]
      raise Faraday::TimeoutError
    end

    if data[:crash]
      raise Exception
    end
  end
end

class OrchestrationJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers

  class TestRepositoryOrchestrationJob < OrchestrationJob
    queue_as :test_repository_orchestration

    def orchestration_type
      "RepositoryOrchestration"
    end
  end

  class TestRepositoryOrchestrationNoQueueJob < OrchestrationJob
    def orchestration_type
      "RepositoryOrchestration"
    end
  end

  fixtures do
    @repo = create(:repository)
    @issue = create(:issue, repository: @repo)
  end

  test "cannot be called directly" do
    assert_raises(OrchestrationJob::DirectCallError) do
      OrchestrationJob.perform_now(1, "SomeOrchestration")
    end
  end

  test "cannot be queued directly" do
    assert_raises(OrchestrationJob::DirectCallError) do
      OrchestrationJob.perform_later(1, "SomeOrchestration")
    end
  end

  test "subclass queue is used" do
    assert_enqueued_jobs 1, only: TestRepositoryOrchestrationJob, queue: :test_repository_orchestration do
      TestRepositoryOrchestrationJob.perform_later(1, "SimpleTestRepositoryOrchestration")
    end
  end

  test "subclass defaults to repository_orchestration queue" do
    assert_enqueued_jobs 1, only: TestRepositoryOrchestrationNoQueueJob, queue: :repository_orchestration do
      TestRepositoryOrchestrationNoQueueJob.perform_later(1, "SimpleTestRepositoryOrchestration")
    end
  end

  test "subclass can be performed" do
    orc = SimpleTestRepositoryOrchestration.create(repository: @repo)
    orc.execute

    assert_nothing_raised do
      TestRepositoryOrchestrationJob.perform_now(orc.id, "SimpleTestRepositoryOrchestration")
    end
    assert_equal "succeeded", orc.reload.state
  end

  test "job retries" do
    orc = SimpleTestRepositoryOrchestration.create(repository: @repo)
    assert_retry_on_dirty_exit(job: TestRepositoryOrchestrationJob, args: [orc.id, "SimpleTestRepositoryOrchestration"])
    assert_retry_on_recoverable_exceptions(job: TestRepositoryOrchestrationJob, args: [orc.id, "SimpleTestRepositoryOrchestration"])
    assert_retry_on_throttler_error(job: TestRepositoryOrchestrationJob, args: [orc.id, "SimpleTestRepositoryOrchestration"])
    assert_retry_on_error GitRPC::Protocol::DGit::ResponseError, TestRepositoryOrchestrationJob, [orc.id, "SimpleTestRepositoryOrchestration"]
    assert_retry_on_error Orchestration::RetryStepError, TestRepositoryOrchestrationJob, [orc.id, "SimpleTestRepositoryOrchestration"]
  end

  test "fails after max attempts" do
    orc = SimpleTestRepositoryOrchestration.create(repository: @repo)
    orc.data[:raise] = true
    orc.save!
    orc.execute

    perform_enqueued_jobs only: TestRepositoryOrchestrationJob do
      TestRepositoryOrchestrationJob.perform_later(orc.id, "SimpleTestRepositoryOrchestration")
    end

    orc.reload
    max_attempts = Orchestration::MAX_ATTEMPTS
    assert_equal max_attempts + 1, orc.attempts
    assert_equal "failed", orc.state
    assert_equal "step_2", orc.step_name
  end

  test "metrics on orchestration success" do
    # Create an orchestration which can be kicked
    orc = SimpleTestRepositoryOrchestration.create(repository: @repo)
    orc.data[:crash] = true
    orc.save!
    orc.execute
    assert_raises Exception do
      TestRepositoryOrchestrationJob.perform_now(orc.id, "SimpleTestRepositoryOrchestration")
    end

    # Update data so we will succeed on kick
    orc.data[:crash] = false
    orc.save!

    TestRepositoryOrchestrationJob.perform_now(orc.id, "SimpleTestRepositoryOrchestration", kicked: true)

    orc.reload
    assert_equal "succeeded", orc.state
    assert_dogstats_increment(1, "repository_orchestration.kick_finish", tags: ["type:SimpleTestRepositoryOrchestration", "state:succeeded"])
  end
end
