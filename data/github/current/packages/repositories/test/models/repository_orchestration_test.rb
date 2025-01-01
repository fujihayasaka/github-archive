# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require_relative "../test_simple_repository_orchestration"
require_relative "../test_repository_orchestration"
require_relative "../test_parent_repository_orchestration"
require_relative "../test_repository_orchestration_only_one_async_skipped_step"
require_relative "../test_repository_orchestration_nothing_after_job_start"
require_relative "./repository_orchestration/concurrent_orchestrations"

class RepositoryOrchestrationTest < GitHub::TestCase
  include DogstatsTestHelpers
  include JobTestHelper
  include PerformanceTestHelpers

  fixtures do
    @repo = create(:public_repository)
    @orchestration = TestRepositoryOrchestration.create(repository: @repo, data: { is_test: true })
  end

  test "populate data" do
    # the data populated by the steps should be empty
    assert_nil @orchestration.data[:step_one_count]
    assert_nil @orchestration.data[:step_two_count]
    assert_nil @orchestration.data[:step_three_count]
    assert_nil @orchestration.data[:step_four_count]
    assert_nil @orchestration.data[:step_five_count]

    # the next step should be step_zero
    assert_equal :step_zero, @orchestration.step_name.to_sym

    assert_equal "created", @orchestration.state
    assert_equal 0, @orchestration.attempts
  end

  test "steps are listed in the correct order" do
    all_steps = @orchestration.class.all_steps
    assert_equal all_steps[0].name.to_sym, :step_zero
    assert_equal all_steps[1].name.to_sym, :step_one
    assert_equal all_steps[2].name.to_sym, :step_two
    assert_equal all_steps[3].name.to_sym, :job_start
    assert_equal all_steps[4].name.to_sym, :step_two_and_a_half
    assert_equal all_steps[5].name.to_sym, :step_three
    assert_equal all_steps[6].name.to_sym, :step_four
    assert_equal all_steps[7].name.to_sym, :step_five
    assert_equal all_steps[8].name.to_sym, :step_six
    assert_nil all_steps[9]
  end

  test "invalid step names" do
    @orchestration.step_name = "foo_bar"
    @orchestration.running!
    @orchestration.save!

    assert_raises(Orchestration::Error) { @orchestration.execute }
    assert_equal :failed, @orchestration.state.to_sym
    assert_equal "Invalid step named '#{@orchestration.step_name}', id #{@orchestration.id}", @orchestration.error_message
  end

  test "cannot define duplicate step names" do
    orchestration_class = Class.new(TestRepositoryOrchestration)
    assert_raises(ArgumentError) do
      orchestration_class.step :foo, {}, &proc { puts "foo" }
      orchestration_class.step :foo, {}, &proc { puts "foo" }
    end
  end

  test "defaults to first step after job_start when running with job_start" do
    @orchestration.step_name = "job_start"
    @orchestration.running!
    @orchestration.save!

    @orchestration.execute
    assert_equal :succeeded, @orchestration.state.to_sym
    # two and a half should still be skipped
    assert_nil @orchestration.data[:step_two_and_a_half_count]
    assert_equal 1, @orchestration.data[:step_three_count]
  end

  test "finishes orchestration if nothing after job_start" do
    orchestration = TestRepositoryOrchestrationNothingAfterJobStart.create(repository: @repo, data: { is_test: true })
    orchestration.step_name = "job_start"
    orchestration.running!
    orchestration.save!

    orchestration.execute
    assert_equal :succeeded, orchestration.state.to_sym
  end

  test "execute returns true if orchestration is executed" do
    assert_equal true, @orchestration.execute
  end

  test "execute the steps and queue the job" do
    assert_enqueued_with(job: RepositoryOrchestrationJob, args: [@orchestration.id, "TestRepositoryOrchestration"]) do
      @orchestration.execute
    end

    # the initialization data should be populated
    assert_equal true, @orchestration.data[:is_test]
    assert_equal @orchestration.repository.id, @orchestration.data[:repo_id]
    assert_equal @orchestration.repository.network.id, @orchestration.data[:network_id]

    assert_enqueued_jobs 1, only: RepositoryOrchestrationJob, queue: :repository_orchestration

    # steps 1 and 2 should have run
    assert_equal 1, @orchestration.data[:step_one_count]
    assert_equal 1, @orchestration.data[:step_two_count]

    # next step should be step_three
    expected_step = "job_start"
    assert_equal expected_step, @orchestration.step_name
    assert_nil @orchestration.data[:step_three_count]
    assert_nil @orchestration.data[:step_four_count]
    assert_nil @orchestration.data[:step_five_count]

    # orchestration should be in the running state
    assert_equal "running", @orchestration.state
    # still on our first attempt, so attempts is 0
    assert_equal 0, @orchestration.attempts

    # finish the orchestration
    @orchestration.execute
    assert_equal "succeeded", @orchestration.state
    # attempts reset to 0 after every successful step
    assert_equal 0, @orchestration.attempts

    # try to run the orchestration again should fail because is already completed
    assert_raises(Orchestration::Error) { @orchestration.execute }
    assert_equal "succeeded", @orchestration.state
    assert_equal 0, @orchestration.attempts

    # try to run the orchestration again with `force` will attempt to run but still fail because is has no more steps to run
    assert_raises(Orchestration::Error) { @orchestration.execute(force: true) }
    assert_equal "succeeded", @orchestration.state
    assert_equal 0, @orchestration.attempts
  end

  test "execute synchronously" do
    @orchestration.execute(synchronous: true)
    assert_enqueued_jobs 0, only: RepositoryOrchestrationJob, queue: :repository_orchestration
    assert_equal 0, @orchestration.attempts
    assert_equal 1, @orchestration.data[:step_one_count]
    assert_equal 1, @orchestration.data[:step_two_count]
    assert_equal 1, @orchestration.data[:step_three_count]
    assert_equal 1, @orchestration.data[:step_four_count]
    assert_equal 1, @orchestration.data[:step_five_count]
    assert_dogstats_increment(1, "repository_orchestration.completed", tags: ["type:#{@orchestration.class.name}", "state:succeeded"])
    assert_dogstats_increment(0, "repository_orchestration.step.retry", tags: ["type:#{@orchestration.class.name}"])
  end

  test "exceptions when running in started state abort the orchestration when no retries are allowed" do
    @orchestration.data[:step_zero_should_raise] = true
    @orchestration.save!
    assert_raises Faraday::TimeoutError do
      @orchestration.execute
    end

    # state should be in the started state and no job should be queued.
    assert_equal "failed", @orchestration.state
    assert_enqueued_jobs 0, only: RepositoryOrchestrationJob, queue: :repository_orchestration
    assert_equal 1, @orchestration.data[:step_zero_count]
    assert_nil @orchestration.data[:step_one_count]
    assert_equal "step_zero", @orchestration.step_name
    assert_equal 1, @orchestration.attempts
    assert_dogstats_increment(1, "repository_orchestration.step.error", tags: ["type:#{@orchestration.class.name}", "step:step_zero"])
  end

  test "non-retryable exceptions when running in started state abort the orchestration" do
    @orchestration.data[:step_one_should_crash] = true
    @orchestration.save!
    assert_raises Exception do
      @orchestration.execute
    end

    assert_equal "failed", @orchestration.state
    # We should have tried the first step twice
    assert_equal 1, @orchestration.data[:step_one_count]
    assert_nil @orchestration.data[:step_two_count]
    assert_equal "step_one", @orchestration.step_name
    assert_dogstats_increment(1, "repository_orchestration.step.error", tags: ["type:#{@orchestration.class.name}", "step:step_one"])
  end

  test "retryable exceptions when running in started state can be retried" do
    @orchestration.data[:step_one_should_raise_once] = true
    @orchestration.save!
    @orchestration.execute

    assert_equal "running", @orchestration.state
    # We should have tried the first step twice
    assert_equal 2, @orchestration.data[:step_one_count]
    assert_equal 1, @orchestration.data[:step_two_count]
    assert_nil @orchestration.data[:step_three_count]
    expected_step = "job_start"
    assert_equal expected_step, @orchestration.step_name
    assert_dogstats_increment(1, "repository_orchestration.step.error", tags: ["type:#{@orchestration.class.name}", "step:step_one"])
  end

  test "retryable exceptions when running in started state are only retried up to max_attempts" do
    @orchestration.data[:step_one_should_raise_in_transaction] = true
    @orchestration.save!
    # Should retry, but fail every time and raise
    assert_raises Faraday::TimeoutError do
      @orchestration.execute
    end

    assert_equal "failed", @orchestration.state
    assert_equal 2, @orchestration.attempts
    # We should have tried the first step twice
    assert_equal 2, @orchestration.data[:step_one_count]
    assert_nil @orchestration.data[:step_two_count]
    assert_equal "step_one", @orchestration.step_name
    assert_dogstats_increment(2, "repository_orchestration.step.error", tags: ["type:#{@orchestration.class.name}", "step:step_one"])
  end

  test "retryable exceptions when running in started state can be retried at most MAX_SYNCHRONOUS_ATTEMPTS_LIMIT times" do
    @orchestration.data[:step_two_should_raise] = true
    @orchestration.save!

    # Should retry, but only MAX_SYNCHRONOUS_ATTEMPTS_LIMIT times
    assert_raises Faraday::TimeoutError do
      @orchestration.execute
    end

    assert_equal "failed", @orchestration.state
    assert_equal Orchestration::MAX_SYNCHRONOUS_ATTEMPTS_LIMIT, @orchestration.attempts
    assert_equal Orchestration::MAX_SYNCHRONOUS_ATTEMPTS_LIMIT, @orchestration.data[:step_two_count]
    assert_nil @orchestration.data[:step_three_count]
    assert_equal "step_two", @orchestration.step_name
    assert_dogstats_increment(Orchestration::MAX_SYNCHRONOUS_ATTEMPTS_LIMIT, "repository_orchestration.step.error", tags: ["type:#{@orchestration.class.name}", "step:step_two"])
  end

  test "exceptions in transaction step when running in started state abort the orchestration" do
    @orchestration.data[:step_one_should_raise_in_transaction] = true
    @orchestration.save!
    assert_raises Faraday::TimeoutError do
      @orchestration.execute
    end

    # state should be failed, and no job should be queued
    assert_equal "failed", @orchestration.reload.state
    assert_enqueued_jobs 0, only: RepositoryOrchestrationJob, queue: :repository_orchestration
  end

  test "exceptions in background steps are retried" do
    @orchestration.data[:step_four_should_raise] = true
    @orchestration.save!

    @orchestration.execute
    assert_enqueued_jobs 1, only: RepositoryOrchestrationJob, queue: :repository_orchestration
    assert_equal "running", @orchestration.state
    expected_step = "job_start"
    assert_equal expected_step, @orchestration.step_name
    assert_equal 0, @orchestration.attempts
    assert_dogstats_increment(0, "repository_orchestration.step.retry", tags: ["type:#{@orchestration.class.name}", "step:step_three"])

    assert_raises Faraday::TimeoutError do
      @orchestration.execute
    end

    @orchestration.reload

    assert_equal 1, @orchestration.attempts
    assert_equal "step_four", @orchestration.step_name
    assert_equal "running", @orchestration.state
    assert_dogstats_increment(0, "repository_orchestration.step.retry", tags: ["type:#{@orchestration.class.name}", "step:step_four"])

    assert_raises Faraday::TimeoutError do
      @orchestration.execute
    end

    @orchestration.reload

    assert_equal 2, @orchestration.attempts
    assert_dogstats_increment(1, "repository_orchestration.step.retry", tags: ["type:#{@orchestration.class.name}", "step:step_four"])
    assert_equal "step_four", @orchestration.step_name
    assert_equal "running", @orchestration.state

    @orchestration.data[:step_four_should_raise] = false
    @orchestration.save!
    @orchestration.execute

    @orchestration.reload

    # attempts reset to 0 when a step succeeds
    assert_equal 0, @orchestration.attempts
    assert_dogstats_increment(2, "repository_orchestration.step.retry", tags: ["type:#{@orchestration.class.name}", "step:step_four"])
    assert_nil @orchestration.step_name
    assert_equal :succeeded, @orchestration.state.to_sym
    assert_equal 1, @orchestration.data[:step_one_count]
    assert_equal 1, @orchestration.data[:step_two_count]
    assert_equal 1, @orchestration.data[:step_three_count]
    assert_equal 3, @orchestration.data[:step_four_count]
    assert_equal 1, @orchestration.data[:step_five_count]
  end

  test "orchestrations eventually fail" do
    @orchestration.data[:step_four_should_raise] = true
    @orchestration.save!

    # first execution just queues the job
    @orchestration.execute
    assert_dogstats_increment(0, "repository_orchestration.step.retry", tags: ["type:#{@orchestration.class.name}", "step:step_four"])

    max_attempts = Orchestration::MAX_ATTEMPTS

    max_attempts.times do
      assert_raises Faraday::TimeoutError do
        @orchestration.execute(synchronous: true)
      end
    end
    assert_dogstats_increment(max_attempts - 1, "repository_orchestration.step.retry", tags: ["type:#{@orchestration.class.name}", "step:step_four"])

    # the next time should throw the MaxAttemptsError
    assert_raises Orchestration::MaxAttemptsError do
      @orchestration.execute
    end

    @orchestration.reload

    assert_equal max_attempts + 1, @orchestration.attempts
    assert_equal :step_four, @orchestration.step_name.to_sym
    assert_equal :failed, @orchestration.state.to_sym
    assert_dogstats_increment(1, "repository_orchestration.completed", tags: ["type:#{@orchestration.class.name}", "state:failed", "step:step_four"])
    assert_dogstats_increment(max_attempts, "repository_orchestration.step.retry", tags: ["type:#{@orchestration.class.name}", "step:step_four"])
  end

  test "synchronous orchestrations fail and can restart" do
    @orchestration.data[:step_four_should_raise] = true
    @orchestration.save!

    # we can restart a synchronous orchestration multiple times, which is handy for retrying failures in production shell
    Orchestration::MAX_ATTEMPTS.times do
      assert_raises Faraday::TimeoutError do
        @orchestration.execute(synchronous: true, force: true)
        assert_predicate @orchestration, :failed?
      end
    end

    @orchestration.reload

    assert_equal Orchestration::MAX_ATTEMPTS, @orchestration.attempts
    assert_equal :step_four, @orchestration.step_name.to_sym
    assert_equal :failed, @orchestration.state.to_sym
    assert_dogstats_increment(1, "repository_orchestration.completed", tags: ["type:#{@orchestration.class.name}", "state:failed", "step:step_four"])

    # should run and throw again because force: true
    assert_raises Faraday::TimeoutError do
      @orchestration.execute(synchronous: true, force: true)
    end

    @orchestration.reload

    assert_equal Orchestration::MAX_ATTEMPTS + 1, @orchestration.attempts
    assert_equal :step_four, @orchestration.step_name.to_sym
    assert_equal :failed, @orchestration.state.to_sym
    assert_dogstats_increment(1, "repository_orchestration.completed", tags: ["type:#{@orchestration.class.name}", "state:failed", "step:step_four"])
  end

  test "started orchestrations fail within execute! code" do
    # Introduce a failure in the execute! code itself, not within a step
    @orchestration.stubs(:log_info).raises(StandardError)

    assert_raises StandardError do
      @orchestration.execute(synchronous: true)
    end

    @orchestration.reload
    assert_equal :failed, @orchestration.state.to_sym
    assert_equal :step_zero, @orchestration.step_name.to_sym
    assert_equal 1, @orchestration.attempts
  end

  test "created orchestrations fail within execute! code" do
    # Introduce a failure in the execute! code itself, not within a step
    @orchestration.stubs(:update!).raises(StandardError)

    assert_raises StandardError do
      @orchestration.execute(synchronous: true)
    end

    @orchestration.reload
    assert_equal :failed, @orchestration.state.to_sym
    assert_equal :step_zero, @orchestration.step_name.to_sym
    assert_equal 0, @orchestration.attempts
  end

  test "validation failures" do
    # start the first orchestration, should queue the job and be running
    o1 = @orchestration
    o1.execute
    assert_equal :running, o1.state.to_sym

    # validate should fail because the other orchestration is running
    assert_raises ActiveRecord::RecordInvalid do
      TestRepositoryOrchestration.create!(repository: @repo, data: nil)
    end

    # finish the running orchestration
    o1.execute
    assert_equal :succeeded, o1.state.to_sym
  end

  test "skip if another is started" do
    # two orchestrations start at the same time
    o1 = @orchestration

    # move the first one to started state
    o1.started!
    assert_equal :started, o1.state.to_sym

    # 2nd one should abort
    assert_raises ActiveRecord::RecordInvalid do
      o2 = TestRepositoryOrchestration.create!(repository: @repo, data: nil)
    end
  end

  test "raise if another is running" do
    # two orchestrations start at the same time
    o1 = @orchestration
    # run the first one, it should stop after queing the job, in the running state
    o1.execute
    assert_equal :running, o1.state.to_sym

    # 2nd one should abort
    assert_raises ActiveRecord::RecordInvalid do
      o2 = TestRepositoryOrchestration.create!(repository: @repo, data: nil)
    end
  end

  test "raise if another is started" do
    # two orchestrations start at the same time, synchronously
    o1 = @orchestration

    # run the first one, it should stop after queing the job
    o1.started!
    assert_equal :started, o1.state.to_sym

    # 2nd one should abort without saving an orchestration record
    assert_raises ActiveRecord::RecordInvalid do
      o2 = TestRepositoryOrchestration.create!(repository: @repo, data: nil)
    end
    assert_equal 1, TestRepositoryOrchestration.all.count
  end

  test "execute! raises, execute returns fails if duplicate" do
    # two orchestrations start at the same time, synchronously
    o1 = @orchestration

    # run the first one, it should stop after queing the job
    o1.started!
    assert_equal :started, o1.state.to_sym

    # 2nd one should abort without saving an orchestration record
    o2 = TestRepositoryOrchestration.create(repository: @repo, data: nil)
    refute o2.valid?
    assert_equal false, o2.execute
    assert_raises Orchestration::ValidationError do
      o2.execute!
    end

    assert_equal :base, o2.errors.first.attribute
    assert_equal :duplicate, o2.errors.first.type
    assert_equal "orchestration in progress #{o1.id}", o2.errors.first.message
    assert_equal 1, TestRepositoryOrchestration.all.count

  end

  test "create should not raise but create! should" do
    o1 = @orchestration
    o2 = TestRepositoryOrchestration.create(repository: @repo, data: nil)
    assert o1.valid?
    refute o2.valid?
    assert_raises ActiveRecord::RecordInvalid do
      TestRepositoryOrchestration.create!(repository: @repo, data: nil)
    end
  end


  test "can exit orchestrations early with skip!" do
    @orchestration.data[:step_two_should_skip] = true
    @orchestration.save

    @orchestration.execute

    assert_equal 1, @orchestration.attempts
    assert_equal :skipped, @orchestration.state.to_sym
    assert_equal :step_two, @orchestration.step_name.to_sym
    assert_dogstats_increment(1, "repository_orchestration.completed", tags: ["type:#{@orchestration.class.name}", "state:skipped", "step:step_two"])
  end

  test "can exit orchestrations early with fail! without raising" do
    @orchestration.data[:step_two_should_fail] = true
    @orchestration.save

    assert_nothing_raised do
      @orchestration.execute
    end

    assert_equal "Orchestration::Error", Failbot.exception_classname_from_hash(Failbot.reports.last)
    assert_equal 1, @orchestration.attempts
    assert_equal :failed, @orchestration.state.to_sym
    assert_equal :step_two, @orchestration.step_name.to_sym
    assert_dogstats_increment(1, "repository_orchestration.completed", tags: ["type:#{@orchestration.class.name}", "state:failed", "step:step_two"])
  end

  test "validation fails if repository is not defined" do
    assert_raises do
      TestRepositoryOrchestration.create!
    end

    assert_raises do
      @orchestration.update!(repository_id: nil)
    end
  end

  test "can run sub-orchestrations" do
    repo = create :repository
    repo1 = create :repository
    repo2 = create :repository
    repo_ids = [repo1.id, repo2.id]
    parent = TestParentRepositoryOrchestration.create(repository: repo, data: { repo_ids: repo_ids })
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      parent.execute
    end
    parent.reload
    assert_equal :succeeded, parent.state.to_sym
    childs_ids = parent.data[:child_ids]
    child1 = TestRepositoryOrchestration.find(childs_ids[0])
    child2 = TestRepositoryOrchestration.find(childs_ids[1])
    assert_equal :succeeded, child1.state.to_sym
    assert_equal :succeeded, child2.state.to_sym
  end

  test "fail if sub-orchestrations fail in job" do
    repo = create :repository
    repo1 = create :repository
    repo2 = create :repository
    repo_ids = [repo1.id, repo2.id]
    parent = TestParentRepositoryOrchestration.create(repository: repo, data: { repo_ids: repo_ids, child_should_raise_in_job: true })
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      parent.execute
    end
    parent.reload
    assert_equal :failed, parent.state.to_sym
    child_ids = parent.data[:child_ids]
    child1 = TestRepositoryOrchestration.find(child_ids[0])
    child2 = TestRepositoryOrchestration.find(child_ids[1])
    assert_equal :failed, child1.state.to_sym
    assert_equal :succeeded, child2.state.to_sym
  end

  test "fail if sub-orchestrations fail during start" do
    repo = create :repository
    repo1 = create :repository
    repo2 = create :repository
    repo_ids = [repo1.id, repo2.id]
    parent = TestParentRepositoryOrchestration.create(repository: repo, data: { repo_ids: repo_ids, child_should_raise_in_start: true })
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      parent.execute
    end
    parent.reload

    assert_equal :failed, parent.state.to_sym
    assert_equal :queue_children, parent.step_name&.to_sym
    assert_equal 2, parent.attempts # should have tried once and then failed on 2nd attempt

    # we defined 2 repos above, so we expect 2 child orchestrations
    # the parent orchestration step only runs once, so it should old create 2 children, one time
    children = RepositoryOrchestration.where(parent_id: parent.id)
    assert_equal 2, children.count
  end

  test "block if sub-orchestrations fail and retry" do
    repo = create :repository
    repo1 = create :repository
    repo2 = create :repository
    repo_ids = [repo1.id, repo2.id]
    parent = TestParentRepositoryOrchestration.create(repository: repo, data: { repo_ids: repo_ids, child_should_crash_in_job: true })
    parent.execute
    RepositoryOrchestrationJob.perform_now(parent.id, parent.class.to_s)
    parent.reload
    assert_equal :waiting, parent.state.to_sym
    assert_equal :finish_step, parent.step_name&.to_sym

    child_ids = parent.data[:child_ids]
    child1 = TestRepositoryOrchestration.find(child_ids[0])
    child2 = TestRepositoryOrchestration.find(child_ids[1])

    RepositoryOrchestrationJob.perform_now(parent.id, parent.class.to_s)
    parent.reload
    assert_equal :waiting, parent.state.to_sym
    assert_equal :finish_step, parent.step_name&.to_sym

    RepositoryOrchestrationJob.perform_now(child2.id, child2.class.to_s)
    assert_equal :succeeded, child2.reload.state.to_sym
    parent.reload
    assert_equal :waiting, parent.state.to_sym
    assert_equal :finish_step, parent.step_name&.to_sym

    RepositoryOrchestrationJob.perform_now(parent.id, parent.class.to_s)
    parent.reload
    assert_equal :waiting, parent.state.to_sym
    assert_equal :finish_step, parent.step_name&.to_sym

    child1.reload.data[:step_four_should_crash] = false
    child1.save!
    RepositoryOrchestrationJob.perform_now(child1.id, child1.class.to_s)
    assert_equal :succeeded, child1.reload.state.to_sym
    parent.reload
    assert_equal :running, parent.state.to_sym
    assert_equal :finish_step, parent.step_name&.to_sym

    RepositoryOrchestrationJob.perform_now(parent.id, parent.class.to_s)
    parent.reload
    assert_equal :succeeded, parent.state.to_sym
    assert_nil parent.step_name
  end

  test "queue the job with delay time" do
    @orchestration.class.job_start_delay = 5.minutes

    original_enqueued_jobs = enqueued_jobs.dup

    @orchestration.execute

    jobs = (enqueued_jobs - original_enqueued_jobs).select { |el| el["job_class"] == "RepositoryOrchestrationJob" }

    assert_equal 1, jobs.size

    job = jobs.first

    enqueued_at = Time.at(job["initially_enqueued_at"])
    wait_until = Time.at(job[:at])

    assert_operator wait_until, :>, enqueued_at
  end

  test "stop after step" do
    TestRepositoryOrchestration.stop_after_step = :step_one
    @orchestration.execute
    @orchestration.reload
    assert_equal :started, @orchestration.state.to_sym
    assert_equal :step_two, @orchestration.step_name.to_sym
    # confirm stop_after_step is reset to avoid flaky tests
    assert_nil TestRepositoryOrchestration.stop_after_step

    TestRepositoryOrchestration.stop_after_step = :step_three
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @orchestration.execute }
    @orchestration.reload
    assert_equal :running, @orchestration.state.to_sym
    assert_equal :step_four, @orchestration.step_name.to_sym

    @orchestration.execute
    @orchestration.reload
    assert_equal :succeeded, @orchestration.state.to_sym
    assert_nil @orchestration.step_name
  end

  test "skip step_two_and_a_half for a clean execution" do
    assert_nil @orchestration.data[:step_two_count]
    assert_nil @orchestration.data[:step_two_and_a_half_count]
    assert_nil @orchestration.data[:step_three_count]
    assert_nil @orchestration.data[:step_six_count]

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @orchestration.execute }
    @orchestration.reload

    assert_equal :succeeded, @orchestration.state.to_sym
    assert_equal 1, @orchestration.data[:step_two_count]
    assert_nil @orchestration.data[:step_two_and_a_half_count]
    assert_equal 1, @orchestration.data[:step_three_count]
    assert_nil @orchestration.data[:step_six_count]
  end

  test "doesn't enqueue skipped step" do
    assert_nil @orchestration.data[:step_two_count]
    assert_nil @orchestration.data[:step_two_and_a_half_count]
    assert_nil @orchestration.data[:step_three_count]

    @orchestration.execute
    @orchestration.reload

    expected_step = "job_start"
    assert_equal expected_step, @orchestration.step_name
  end

  test "skip step_two_and_a_half when kicked from the database" do
    assert_nil @orchestration.data[:step_two_count]
    assert_nil @orchestration.data[:step_two_and_a_half_count]
    assert_nil @orchestration.data[:step_three_count]

    @orchestration.execute
    @orchestration.reload

    assert_equal 1, @orchestration.data[:step_two_count]
    assert_nil @orchestration.data[:step_two_and_a_half_count]
    assert_nil @orchestration.data[:step_three_count]
    assert_nil @orchestration.data[:step_six_count]

    @orchestration.update!(step_name: :step_two_and_a_half)

    perform_enqueued_jobs(only: RepositoryOrchestrationJob)
    @orchestration.reload

    assert_equal :succeeded, @orchestration.state.to_sym

    assert_equal 1, @orchestration.data[:step_two_count]
    assert_nil @orchestration.data[:step_two_and_a_half_count]
    assert_equal 1, @orchestration.data[:step_three_count]
    assert_nil @orchestration.data[:step_six_count]
  end

  test "skip last async step when there is only one async step" do
    o = TestRepositoryOrchestrationOnlyOneAsyncSkippedStep.create(repository: @repo, data: { is_test: true })

    assert_nil o.data[:step_zero_count]

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
    o.reload

    assert_equal :succeeded, o.state.to_sym
    assert_equal 1, o.data[:step_zero_count]
    assert_nil o.data[:last_one_count]
  end

  test "does not save job_start step into the DB" do
    TestRepositoryOrchestration.stop_after_step = :step_two # The step right before job_start
    @orchestration.execute
    @orchestration.reload
    assert_equal :started, @orchestration.state.to_sym
    assert_equal :step_two, @orchestration.step_name.to_sym
    # confirm stop_after_step is reset to avoid flaky tests
    assert_nil TestRepositoryOrchestration.stop_after_step

    TestRepositoryOrchestration.stop_after_step = :step_three
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @orchestration.execute }
    @orchestration.reload
    assert_equal :running, @orchestration.state.to_sym
    assert_equal :step_four, @orchestration.step_name.to_sym

    @orchestration.execute
    @orchestration.reload
    assert_equal :succeeded, @orchestration.state.to_sym
    assert_nil @orchestration.step_name
  end

  test "simple orchestration queries" do
    repository = create(:public_repository)
    o = TestSimpleRepositoryOrchestration.create(repository: repository, data: { is_test: true })

    assert_nil o.data[:sync_step_count]
    assert_nil o.data[:async_step_count]

    q = [
      #sync queries portion

      # Updating the state created(0) -> started(1)
      "UPDATE repository_orchestrations SET repository_orchestrations.state = ? WHERE repository_orchestrations.type = 'TestSimpleRepositoryOrchestration' AND repository_orchestrations.id = ? AND repository_orchestrations.state = ? AND (NOT EXISTS (SELECT id FROM (SELECT repository_orchestrations.* FROM repository_orchestrations WHERE repository_orchestrations.type = 'TestSimpleRepositoryOrchestration' AND repository_orchestrations.id != ? AND repository_orchestrations.state IN ? AND repository_orchestrations.repository_id = ?) as in_progress_orchestrations))",
      "UPDATE repository_orchestrations SET repository_orchestrations.state = ?, repository_orchestrations.updated_at = '? ?:?:?' WHERE repository_orchestrations.id = ?",

      # Moving the attempts from 0 -> 1
      "UPDATE repository_orchestrations SET repository_orchestrations.data = '---\\n:is_test: ?\\n:synchronous: ?\\n', repository_orchestrations.attempts = ?, repository_orchestrations.updated_at = '? ?:?:?' WHERE repository_orchestrations.id = ?",

      # After job_start to trigger after commit callback queue_orchestration_job
      "UPDATE repository_orchestrations SET repository_orchestrations.state = ?, repository_orchestrations.step_name = 'job_start', repository_orchestrations.data = '---\\n:is_test: ?\\n:synchronous: ?\\n:sync_step_count: ?\\n', repository_orchestrations.attempts = ?, repository_orchestrations.updated_at = '? ?:?:?' WHERE repository_orchestrations.id = ?",
      # async portion queries
      "SELECT repository_orchestrations.* FROM repository_orchestrations WHERE repository_orchestrations.type = 'TestSimpleRepositoryOrchestration' AND repository_orchestrations.id = ? LIMIT ?",
      "SELECT repositories.* FROM repositories WHERE repositories.id = ? LIMIT ?",

      # Setting the current step to the step after job_start
      "UPDATE repository_orchestrations SET repository_orchestrations.step_name = 'async_step', repository_orchestrations.updated_at = '? ?:?:?' WHERE repository_orchestrations.id = ?",

      # Moving the attempts from 0 -> 1
      "UPDATE repository_orchestrations SET repository_orchestrations.attempts = ?, repository_orchestrations.updated_at = '? ?:?:?' WHERE repository_orchestrations.id = ?",
      # after last step
      "UPDATE repository_orchestrations SET repository_orchestrations.step_name = NULL, repository_orchestrations.data = '---\\n:is_test: ?\\n:synchronous: ?\\n:sync_step_count: ?\\n:async_step_count: ?\\n', repository_orchestrations.attempts = ?, repository_orchestrations.updated_at = '? ?:?:?' WHERE repository_orchestrations.id = ?",

      # end orchestration
      "UPDATE repository_orchestrations SET repository_orchestrations.state = ?, repository_orchestrations.updated_at = '? ?:?:?' WHERE repository_orchestrations.id = ?"
    ]

    assert_sql_queries(q) do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        o.execute
      end
    end

    o.reload

    assert_equal :succeeded, o.state.to_sym
    assert_equal 1, o.data[:sync_step_count]
    assert_equal 1, o.data[:async_step_count]
  end

  test "#concurrent_orchestrations" do
    repo = create(:repository)

    o = TestConcurrentOrchestration.create(repository: repo, data: { depth: 0 })
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      o.execute
    end

    assert_equal 2, o.concurrent_orchestrations.count

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      RepositoryOrchestration.where(repository: repo).each(&:execute!)
    end

    assert_equal 0, o.concurrent_orchestrations.count
  end

  test "base_orchestration_name" do
    assert_equal "repository_orchestration", RepositoryOrchestration.base_orchestration_name
    assert_equal "repository_orchestration", RepositoryOrchestration.new.base_orchestration_name
  end

  test "prevent overlapping orchestrations" do
    orchestration2 = TestRepositoryOrchestration.new(repository: @repo, data: { is_test: true })
    orchestration2.save!(validate: false)
    orchestration2.errors.clear

    @orchestration.execute
    orchestration2.execute

    # Simulating the job pick up
    @orchestration.execute

    assert @orchestration.succeeded?
    assert orchestration2.skipped?
  end

  class OrchestrationMultiTenantTest < GitHub::TestCase
    fixtures do
      on_multi_tenant_enterprise do
        owner = create :emu
        @repo = create(:public_repository, owner: owner)
        @orchestration = TestRepositoryOrchestration.create(repository: @repo, data: { is_test: true })
      end
    end

    setup do
      on_multi_tenant_enterprise(tenant: @repo.owner.enterprise_managed_business)
    end

    test "sets the tenant context in proxima if not present in execute" do
      GitHub::CurrentTenant.remove

      @orchestration.execute
      job_data = ApplicationJob.queue_adapter.enqueued_jobs.find do |enqueued|
        enqueued[:job] == RepositoryOrchestrationJob && enqueued[:args] == [@orchestration&.id, @orchestration&.type]
      end

      refute_nil @orchestration
      assert_equal @repo.tenant_id, job_data["X-GitHub-Tenant-ID"]
      assert_nil GitHub::CurrentTenant.get
    end

    test "sets the tenant context in proxima if not present in execute!" do
      GitHub::CurrentTenant.remove

      @orchestration.execute!
      job_data = ApplicationJob.queue_adapter.enqueued_jobs.find do |enqueued|
        enqueued[:job] == RepositoryOrchestrationJob && enqueued[:args] == [@orchestration&.id, @orchestration&.type]
      end

      refute_nil @orchestration
      assert_equal @repo.tenant_id, job_data["X-GitHub-Tenant-ID"]
      assert_nil GitHub::CurrentTenant.get
    end

    test "does not set the tenant context in proxima if already present" do
      GitHub::CurrentTenant.stubs(:set).raises(StandardError.new("Should not be called"))

      @orchestration.execute
      job_data = ApplicationJob.queue_adapter.enqueued_jobs.find do |enqueued|
        enqueued[:job] == RepositoryOrchestrationJob && enqueued[:args] == [@orchestration&.id, @orchestration&.type]
      end

      refute_nil @orchestration
      assert_equal @repo.tenant_id, job_data["X-GitHub-Tenant-ID"]
      refute_nil GitHub::CurrentTenant.get
    end

    test "does not set the tenant context in proxima if repository is not present" do
      GitHub::CurrentTenant.remove
      GitHub::CurrentTenant.stubs(:set).raises(StandardError.new("Should not be called"))

      TestRepositoryOrchestration.any_instance.stubs(:repository).returns(nil)

      # Orchestration will raise due to lack of repo, but does not raise due to attempting to set tenant
      assert_raises(TypeError) do
        @orchestration.execute
      end
      assert_nil GitHub::CurrentTenant.get
    end
  end
end
