# typed: true
# frozen_string_literal: true
require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/issues_orchestration_test_helper"
require_relative "test_issue_comment_orchestration"

class IssueCommentOrchestrationTest < GitHub::TestCase
  include IssuesOrchestrationTestHelper
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @issue = create(:issue, :wait_for_orchestration, repository: @repo, user: @user)
    @comment = create(:issue_comment, :wait_for_orchestration, repository: @repo, user: @user, issue: @issue)
  end

  test "base_orchestration_name" do
    assert_equal "issue_comment_orchestration", IssueCommentOrchestration.base_orchestration_name
    assert_equal "issue_comment_orchestration", IssueCommentOrchestration.new.base_orchestration_name
  end

  test "ensure create callback orderings", feature_enabled: :instrument_rails_callbacks do
    after_commit_invocation_order = log_after_commit_invocation_order do
      create(:issue_comment, repository: @repo, issue: @issue)
    end

    assert after_commit_invocation_order.size > 1
    assert_equal "execute_create_issue_comment_orchestration", after_commit_invocation_order.first
  end

  test "kick stuck IssueCommentOrchestrations and delete old records" do
    # create an orchestration that fails in the started state
    data = {}

    o2 = TestIssueCommentOrchestration.create(repository: @repo, issue: @issue, issue_comment: @comment, data: { step_two_should_raise: true })
    assert_raises Faraday::TimeoutError do
      o2.execute
    end

    # create 3 more that crash in the job
    (1..3).each do |_i|
      issue = create(:issue, :wait_for_orchestration, repository: @repo)
      comment = create(:issue_comment, :wait_for_orchestration, repository: @repo, issue: @issue)
      data = { step_four_should_crash: true }
      orchestration = TestIssueCommentOrchestration.create(repository: @repo, issue: issue, issue_comment: comment, data: data)
      assert_predicate orchestration, :valid?
      perform_enqueued_jobs(only: [IssueCommentOrchestration.job_class]) do
        # should crash
        assert_raises Exception do
          orchestration.execute

        end
      end
      orchestration.reload
      orchestration.data[:step_four_should_crash] = false
      orchestration.update(data: orchestration.data)
    end

    assert_equal 0, TestIssueCommentOrchestration.started.count
    assert_equal 3, TestIssueCommentOrchestration.running.count
    assert_equal 1, TestIssueCommentOrchestration.failed.count
    assert_dogstats_increment(1, "issue_comment_orchestration.completed", tags: ["type:TestIssueCommentOrchestration", "state:failed"])

    # running the sweeper job now should do nothing
    perform_enqueued_jobs(only: [IssueCommentOrchestration.job_class]) do
      IssueOrchestrationSweeperJob.perform_now
    end

    assert_equal 3, TestIssueCommentOrchestration.running.count
    assert_dogstats_increment(0, "issue_comment_orchestration.completed", tags: ["type:TestIssueCommentOrchestration", "state:succeeded"])

    TestIssueCommentOrchestration.running.update_all(updated_at: Time.now - Orchestration::STALE_TIME - 1.minute)
    # running the sweeper job now should kick the running orchestrations
    perform_enqueued_jobs(only: [IssueCommentOrchestration.job_class]) do
      IssueOrchestrationSweeperJob.perform_now
    end

    assert_equal 0, TestIssueCommentOrchestration.running.count
    assert_dogstats_increment(3, "issue_comment_orchestration.completed", tags: ["type:TestIssueCommentOrchestration", "state:succeeded"])

    TestIssueCommentOrchestration.started.update_all(updated_at: Time.now - Orchestration::STALE_TIME - 1.minute)
    # running the sweeper job now should finish the started orchestrations
    perform_enqueued_jobs(only: [IssueCommentOrchestration.job_class]) do
      IssueOrchestrationSweeperJob.perform_now
    end

    assert_equal 0, TestIssueCommentOrchestration.started.count
    assert_equal 0, TestIssueCommentOrchestration.running.count
    assert_equal 3, TestIssueCommentOrchestration.succeeded.count
    assert_equal 1, TestIssueCommentOrchestration.failed.count
    assert_equal 4, TestIssueCommentOrchestration.completed.count
    assert_equal 4, TestIssueCommentOrchestration.all.count

    assert_dogstats_increment(3, "issue_comment_orchestration.completed", tags: ["type:TestIssueCommentOrchestration", "state:succeeded"])
    assert_dogstats_gauge_value(3, "issue_comment_orchestration.stale", tags: ["type:TestIssueCommentOrchestration", "step:step_four"])

    # delete old completed orchestrations
    TestIssueCommentOrchestration.update_all(updated_at: Orchestration::RETENTION_LIMIT.ago - 1.minute)
    IssueOrchestrationSweeperJob.perform_now

    assert_dogstats_gauge(4, "issue_comment_orchestration.purgeable", tags: ["type:IssueCommentOrchestration"])
    assert_dogstats_count_value(4, "issue_comment_orchestration.purged", tags: ["type:IssueCommentOrchestration"])
    assert_equal 0, TestIssueCommentOrchestration.all.count
  end
end
