# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ReachabilityAnalysisJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  fixtures do
    @user = create :user
    @repo = create :repository, from_example: :simple
  end

  test "starts workflow with appropriate parameters" do
    ReachabilityAnalysisJob.any_instance.expects(:create_workflow_run).with do |params|
      params.values_at(:actor, :repo, :sha) == [@user, @repo, @repo.default_oid]
    end

    ReachabilityAnalysisJob.perform_now(@repo.id, actor: @user.login)
  end

  test "successfully logs workflow id" do
    ReachabilityAnalysisJob.any_instance.expects(:create_workflow_run).returns(12345)

    expected_log = {
      "Body": "Reachability workflow triggered",
      "actor": @user.login,
      "repo.id": @repo.id,
      "sha": @repo.default_oid,
      "success": true,
      "workflow.id": 12345,
    }

    assert_logged(**expected_log) do
      ReachabilityAnalysisJob.perform_now(@repo.id, actor: @user.login)
    end
  end

  test "logs and raises workflow run failure" do
    ReachabilityAnalysisJob.any_instance.stubs(:create_workflow_run).raises(Reachability::ActionsWorkflow::UnableToLaunch)

    assert_logged("success" => false) do
      assert_raises Reachability::ActionsWorkflow::UnableToLaunch do
        ReachabilityAnalysisJob.perform_now(@repo.id, actor: @user.login)
      end
    end
  end

  test "raises error if actor is invalid" do
    assert_raises ReachabilityAnalysisJob::InvalidActorError do
      ReachabilityAnalysisJob.perform_now(@repo.id, actor: "someonewhodoesntexist")
    end
  end

  test "job retries on dirty exit and other errors successfully" do
    assert_retry_conditions job: ReachabilityAnalysisJob, args: [@repo.id, { actor: @user.login }]
  end

  test "locks with repository id" do
    reset_job_hash_locks
    assert_enqueued_jobs 1, only: ReachabilityAnalysisJob do
      job = ReachabilityAnalysisJob.perform_later(@repo.id, actor: @user.login)

      assert_predicate job, :locked?
      assert_equal @repo.id.to_s, T.unsafe(job).lock_key

      ReachabilityAnalysisJob.perform_later(@repo.id, actor: @user.login)
    end
    reset_job_hash_locks
  end
end unless GitHub.single_tenant_enterprise?
