# typed: strict
# frozen_string_literal: true

require "test_helper"
require_relative "../models/test_pull_request_orchestration"

class PullRequestOrchestrationSweeperJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  test "purges old orchestrations" do
    user = create(:user)
    repo = create(:repository, owner: user, from_example: :simple)
    pull = create(:pull_request, :with_mergeable_head, user: user, repository: repo)

    Timecop.freeze(2.days.ago) do
      # create new orchestration and leave it in a 'running' state
      data = { step_one_count: 1, step_two_count: 2 }
      orchestration = TestPullRequestOrchestration.create(repository: repo, pull_request_id: pull.id, data:)
      orchestration.execute
      orchestration.reload
    end

    assert_equal 1, TestPullRequestOrchestration.running.count

    PullRequestOrchestrationSweeperJob.perform_now

    assert_dogstats_gauge(1, "pull_request_orchestration.purgeable", tags: ["type:PullRequestOrchestration"])
    assert_dogstats_count_value(1, "pull_request_orchestration.purged", tags: ["type:PullRequestOrchestration"])
    assert_equal 0, TestPullRequestOrchestration.count
  end

  test "restart stuck orchestrations" do
    # create orchestrations that crash when running asynchronously
    (1..3).each do |_i|
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :simple)
      pull = create(:pull_request, :with_mergeable_head, user: user, repository: repo)
      data = { step_four_should_crash: true }
      orchestration = TestPullRequestOrchestration.create(repository: repo, pull_request_id: pull.id, data:)
      perform_enqueued_jobs(only: [PullRequestOrchestrationJob]) do
        # should crash
        assert_raises Exception do
          orchestration.execute
        end
      end
      orchestration.reload
      orchestration.data[:step_four_should_crash] = false
      orchestration.update(data: orchestration.data)
    end

    assert_equal 0, TestPullRequestOrchestration.started.count
    assert_equal 3, TestPullRequestOrchestration.running.count

    # running the sweeper job now should do nothing
    perform_enqueued_jobs(only: [PullRequestOrchestrationJob]) do
      PullRequestOrchestrationSweeperJob.perform_now
    end
    assert_equal 3, TestPullRequestOrchestration.running.count
    assert_dogstats_increment(0, "pull_request_orchestration.completed", tags: ["type:TestPullRequestOrchestration", "state:succeeded"])

    # update the orchestrations to be stale
    TestPullRequestOrchestration.running.update_all(updated_at: Time.now - PullRequestOrchestration::STALE_TIME - 1.minute)
    # running the sweeper job now should kick the running orchestrations
    Orchestration.stub_const(:SWEEPER_BATCH_SIZE, 1) do
      perform_enqueued_jobs(only: [PullRequestOrchestrationJob]) do
        PullRequestOrchestrationSweeperJob.perform_now
      end
    end

    assert_dogstats_increment(3, "pull_request_orchestration.completed", tags: ["type:TestPullRequestOrchestration", "state:succeeded"])
    assert_equal 0, TestPullRequestOrchestration.started.count
    assert_equal 0, TestPullRequestOrchestration.running.count
    assert_equal 3, TestPullRequestOrchestration.succeeded.count
    assert_equal 3, TestPullRequestOrchestration.completed.count

    assert_dogstats_increment(3, "pull_request_orchestration.completed", tags: ["type:TestPullRequestOrchestration", "state:succeeded"])
    assert_dogstats_gauge_value(3, "pull_request_orchestration.stale", tags: ["type:TestPullRequestOrchestration", "step:step_four"])
  end

  test "marks created orchestrations as abandoned and does not retry" do
    # create an orchestration that fails in the started state
    user = create(:user)
    repo = create(:repository, owner: user, from_example: :simple)
    pull = create(:pull_request, :with_mergeable_head, user: user, repository: repo)
    orchestration = TestPullRequestOrchestration.create(repository: repo, pull_request_id: pull.id)

    assert_equal :created, orchestration.state.to_sym

    orchestration.update(updated_at: Time.now - PullRequestOrchestration::STALE_TIME - 1.minute)
    perform_enqueued_jobs(only: [PullRequestOrchestrationJob]) do
      PullRequestOrchestrationSweeperJob.perform_now
    end

    orchestration.reload
    assert_equal :abandoned, orchestration.state.to_sym
    assert_match /Cannot retry/, orchestration.error_message
    assert_dogstats_increment(1, "pull_request_orchestration.completed", tags: ["type:TestPullRequestOrchestration", "state:abandoned"])
  end

  test "marks started orchestrations as abandoned and does not retry" do
    user = create(:user)
    repo = create(:repository, owner: user, from_example: :simple)
    pull = create(:pull_request, :with_mergeable_head, user: user, repository: repo)
    orchestration = TestPullRequestOrchestration.create(repository: repo, pull_request_id: pull.id)
    orchestration.update(state: :started, step_name: :step_one.to_s)

    assert_equal :started, orchestration.state.to_sym

    orchestration.update(updated_at: Time.now - PullRequestOrchestration::STALE_TIME - 1.minute)
    perform_enqueued_jobs(only: [PullRequestOrchestrationJob]) do
      PullRequestOrchestrationSweeperJob.perform_now
    end

    orchestration.reload
    assert_equal :abandoned, orchestration.state.to_sym
    assert_match /Cannot retry/, orchestration.error_message
    assert_dogstats_increment(1, "pull_request_orchestration.completed", tags: ["type:TestPullRequestOrchestration", "state:abandoned"])
  end
end
