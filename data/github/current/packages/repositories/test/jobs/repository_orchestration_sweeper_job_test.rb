# typed: strict
# frozen_string_literal: true
require "test_helper"
require_relative "../test_repository_orchestration"

class RepositoryOrchestrationSweeperJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  test "run stuck orchestrations and delete old records" do
    # create an orchestration that fails in the started state
    repo = create :repository
    o2 = TestRepositoryOrchestration.create(repository: repo, data: { step_two_should_raise: true })
    assert_raises Faraday::TimeoutError do
      o2.execute
    end

    # create 3 more that crash in the job
    (1..3).each do |_i|
      repo = create :repository
      data = { step_four_should_crash: true }
      orchestration = TestRepositoryOrchestration.create(repository: repo, data: data)
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        # should crash
        assert_raises Exception do
          orchestration.execute
        end
      end
      orchestration.reload
      orchestration.data[:step_four_should_crash] = false
      orchestration.update(data: orchestration.data)
    end

    assert_equal 0, TestRepositoryOrchestration.started.count
    assert_equal 3, TestRepositoryOrchestration.running.count
    assert_equal 1, TestRepositoryOrchestration.failed.count
    assert_dogstats_increment(1, "repository_orchestration.completed", tags: ["type:TestRepositoryOrchestration", "state:failed"])

    # running the sweeper job now should do nothing
    Orchestration.stub_const(:SWEEPER_BATCH_SIZE, 1) do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        RepositoryOrchestrationSweeperJob.perform_now
      end
    end
    assert_equal 3, TestRepositoryOrchestration.running.count
    assert_dogstats_increment(0, "repository_orchestration.completed", tags: ["type:TestRepositoryOrchestration", "state:succeeded"])

    TestRepositoryOrchestration.running.update_all(updated_at: Time.now - Orchestration::STALE_TIME - 1.minute)
    # running the sweeper job now should kick the running orchestrations
    Orchestration.stub_const(:SWEEPER_BATCH_SIZE, 1) do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        RepositoryOrchestrationSweeperJob.perform_now
      end
    end

    assert_equal 0, TestRepositoryOrchestration.running.count
    assert_dogstats_increment(3, "repository_orchestration.completed", tags: ["type:TestRepositoryOrchestration", "state:succeeded"])

    TestRepositoryOrchestration.started.update_all(updated_at: Time.now - Orchestration::STALE_TIME - 1.minute)
    # running the sweeper job now should finish the started orchestrations
    Orchestration.stub_const(:SWEEPER_BATCH_SIZE, 1) do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        RepositoryOrchestrationSweeperJob.perform_now
      end
    end

    assert_equal 0, TestRepositoryOrchestration.started.count
    assert_equal 0, TestRepositoryOrchestration.running.count
    assert_equal 3, TestRepositoryOrchestration.succeeded.count
    assert_equal 1, TestRepositoryOrchestration.failed.count
    assert_equal 4, TestRepositoryOrchestration.completed.count
    assert_equal 4, TestRepositoryOrchestration.all.count

    assert_dogstats_increment(3, "repository_orchestration.completed", tags: ["type:TestRepositoryOrchestration", "state:succeeded"])
    assert_dogstats_gauge_value(3, "repository_orchestration.stale", tags: ["type:TestRepositoryOrchestration", "step:step_four"])

    # delete old completed orchestrations
    TestRepositoryOrchestration.update_all(updated_at: Orchestration::RETENTION_LIMIT.ago - 1.minute)
    RepositoryOrchestrationSweeperJob.perform_now

    assert_dogstats_gauge(4, "repository_orchestration.purgeable", tags: ["type:RepositoryOrchestration"])
    assert_dogstats_count_value(4, "repository_orchestration.purged", tags: ["type:RepositoryOrchestration"])
    assert_equal 0, TestRepositoryOrchestration.all.count
  end

  test "marks created orchestrations as abandoned and does not retry" do
    # create an orchestration that fails in the started state
    repo = create :repository
    o2 = TestRepositoryOrchestration.create(repository: repo)

    assert_equal :created, o2.state.to_sym

    o2.update(updated_at: Time.now - Orchestration::STALE_TIME - 1.minute)
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      RepositoryOrchestrationSweeperJob.perform_now
    end

    o2.reload
    assert_equal :abandoned, o2.state.to_sym
    assert_match /Cannot retry/, o2.error_message
    assert_dogstats_increment(1, "repository_orchestration.completed", tags: ["type:TestRepositoryOrchestration", "state:abandoned"])
  end

  test "marks started orchestrations as abandoned and does not retry" do
    repo = create :repository
    o2 = TestRepositoryOrchestration.create(repository: repo)
    o2.update(state: :started, step_name: :step_one.to_s)

    assert_equal :started, o2.state.to_sym

    o2.update(updated_at: Time.now - Orchestration::STALE_TIME - 1.minute)
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      RepositoryOrchestrationSweeperJob.perform_now
    end

    o2.reload
    assert_equal :abandoned, o2.state.to_sym
    assert_match /Cannot retry/, o2.error_message
    assert_dogstats_increment(1, "repository_orchestration.completed", tags: ["type:TestRepositoryOrchestration", "state:abandoned"])
  end

  test "sets tenant when restarting stuck orchestrations" do
    on_multi_tenant_enterprise do
      owner = create :emu
      repo = create :repository, owner: owner

      data = { step_four_should_crash: true }
      orchestration = TestRepositoryOrchestration.create(repository: repo, data: data)
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        assert_raises Exception do
          orchestration.execute
        end
      end
      orchestration.reload
      orchestration.data[:step_four_should_crash] = false
      orchestration.update(data: orchestration.data)

      TestRepositoryOrchestration.running.update_all(updated_at: Time.now - Orchestration::STALE_TIME - 1.minute)

      assert_nil GitHub::CurrentTenant.get
      Orchestration.stub_const(:SWEEPER_BATCH_SIZE, 1) do
        RepositoryOrchestrationSweeperJob.perform_now
      end

      job_data = ApplicationJob.queue_adapter.enqueued_jobs.find do |enqueued|
        enqueued[:job] == RepositoryOrchestrationJob && enqueued[:args].include?(orchestration.id)
      end
      assert_equal repo.tenant_id, job_data["X-GitHub-Tenant-ID"]
      assert_nil GitHub::CurrentTenant.get
    end
  end
end
