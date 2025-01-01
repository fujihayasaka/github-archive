# typed: true
# frozen_string_literal: true
require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/issues_orchestration_test_helper"
require_relative "test_issue_orchestration"

class IssueOrchestrationTest < GitHub::TestCase
  include DogstatsTestHelpers
  include IssuesOrchestrationTestHelper

  fixtures do
    @repo = create(:repository)
    @issue = create(:issue, :wait_for_orchestration, repository: @repo)
  end

  test "we create an IssueOrchestration" do
    data = {}

    orchestration = TestIssueOrchestration.create(repository: @repo, issue: @issue, data: data)
    orchestration.execute
    orchestration.reload
    assert_equal :running, orchestration.state.to_sym
    expected_step = "job_start"
    assert_equal expected_step, orchestration.step_name
    queue = :issue_orchestration
    assert_enqueued_jobs 1, only: [IssueOrchestration.job_class], queue: queue

    IssueOrchestration.job_class.perform_now(orchestration.id, orchestration.class.to_s)
    orchestration.reload
    assert_equal :succeeded, orchestration.state.to_sym
    assert_nil orchestration.step_name
  end

  test "kick stuck IssueOrchestrations and delete old records" do
    # create an orchestration that fails in the started state
    data = {}

    o2 = TestIssueOrchestration.create(repository: @repo, issue: @issue, data: { step_two_should_raise: true })
    assert_raises Faraday::TimeoutError do
      o2.execute
    end

    # create 3 more that crash in the job
    (1..3).each do |_i|
      repo = create(:repository)
      issue = create(:issue, :wait_for_orchestration, repository: repo)
      data = { step_four_should_crash: true }
      orchestration = TestIssueOrchestration.create(repository: repo, issue: issue, data: data)
      assert_predicate orchestration, :valid?
      perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
        # should crash
        assert_raises Exception do
          orchestration.execute
        end
      end
      orchestration.reload
      orchestration.data[:step_four_should_crash] = false
      orchestration.update(data: orchestration.data)
    end

    assert_equal 0, TestIssueOrchestration.started.count
    assert_equal 3, TestIssueOrchestration.running.count
    assert_equal 1, TestIssueOrchestration.failed.count
    assert_dogstats_increment(1, "issue_orchestration.completed", tags: ["type:TestIssueOrchestration", "state:failed"])

    # running the sweeper job now should do nothing
    perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
      IssueOrchestrationSweeperJob.perform_now
    end

    assert_equal 3, TestIssueOrchestration.running.count
    assert_dogstats_increment(0, "issue_orchestration.completed", tags: ["type:TestIssueOrchestration", "state:succeeded"])

    TestIssueOrchestration.running.update_all(updated_at: Time.now - Orchestration::STALE_TIME - 1.minute)
    # running the sweeper job now should kick the running orchestrations
    perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
      IssueOrchestrationSweeperJob.perform_now
    end

    assert_equal 0, TestIssueOrchestration.running.count
    assert_dogstats_increment(3, "issue_orchestration.completed", tags: ["type:TestIssueOrchestration", "state:succeeded"])

    TestIssueOrchestration.started.update_all(updated_at: Time.now - Orchestration::STALE_TIME - 1.minute)
    # running the sweeper job now should finish the started orchestrations
    perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
      IssueOrchestrationSweeperJob.perform_now
    end

    assert_equal 0, TestIssueOrchestration.started.count
    assert_equal 0, TestIssueOrchestration.running.count
    assert_equal 3, TestIssueOrchestration.succeeded.count
    assert_equal 1, TestIssueOrchestration.failed.count
    assert_equal 4, TestIssueOrchestration.completed.count
    assert_equal 4, TestIssueOrchestration.all.count

    assert_dogstats_increment(3, "issue_orchestration.completed", tags: ["type:TestIssueOrchestration", "state:succeeded"])
    assert_dogstats_gauge_value(3, "issue_orchestration.stale", tags: ["type:TestIssueOrchestration", "step:step_four"])

    # delete old completed orchestrations
    TestIssueOrchestration.update_all(updated_at: Orchestration::RETENTION_LIMIT.ago - 1.minute)
    IssueOrchestrationSweeperJob.perform_now

    assert_dogstats_gauge(4, "issue_orchestration.purgeable", tags: ["type:IssueOrchestration"])
    assert_dogstats_count_value(4, "issue_orchestration.purged", tags: ["type:IssueOrchestration"])
    assert_equal 0, TestIssueOrchestration.all.count
  end

  test "we set a base name for the orchestration" do
    assert_equal "issue_orchestration", IssueOrchestration.base_orchestration_name
    assert_equal "issue_orchestration", IssueOrchestration.new.base_orchestration_name
  end

  test "fails on duplicate orchestrations" do
    orchestration_1 = TestIssueOrchestration.create(repository: @repo, issue: @issue, data: {})
    orchestration_2 = TestIssueOrchestration.create(repository: @repo, issue: @issue, data: {})

    assert_empty orchestration_1.errors
    refute_empty orchestration_2.errors
  end

  test "ensure create callback orderings", feature_enabled: :instrument_rails_callbacks do
    after_commit_invocation_order = log_after_commit_invocation_order do
      create(:issue, repository: @repo)
    end

    assert after_commit_invocation_order.size > 1
    assert_equal "execute_create_issue_orchestration", after_commit_invocation_order.first
  end

  test "ensure update callback orderings", feature_enabled: :instrument_rails_callbacks do
    issue = create(:issue, repository: @repo)

    after_commit_invocation_order = log_after_commit_invocation_order do
      issue.update(title: "hello")
    end

    assert after_commit_invocation_order.size > 1
    assert_equal "execute_update_issue_orchestration", after_commit_invocation_order.first
  end
end
