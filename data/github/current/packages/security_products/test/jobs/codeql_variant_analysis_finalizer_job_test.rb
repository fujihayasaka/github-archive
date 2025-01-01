# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodeqlVariantAnalysisCleanupJobTest < GitHub::TestCase
  fixtures do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @actions_app = create :launch_integration
    GitHub.stubs(:launch_github_app).returns(@actions_app)

    @controller_repo = create(:repository)

    @in_progress_variant_analysis = create(
      :codeql_variant_analysis,
      controller_repo: @controller_repo,
      actions_workflow_run: create_workflow_run(:in_progress))
    @completed_variant_analysis = create(
      :codeql_variant_analysis,
      controller_repo: @controller_repo,
      actions_workflow_run: create_workflow_run(:completed))
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  def create_workflow_run(status)
    check_suite = create(:check_suite_for_actions_app, :with_push, repository: @controller_repo)
    workflow_run = check_suite.workflow_run

    if status == :in_progress
      check_suite.conclusion = nil
      check_suite.status = ::CheckRun.statuses[:in_progress]
    elsif status == :completed
      check_suite.conclusion = ::CheckRun.conclusions[:success]
      check_suite.status = ::CheckRun.statuses[:completed]
    else
      raise "Unknown status: #{status}"
    end
    check_suite.save!

    workflow_run
  end

  def create_repo_task(variant_analysis, status)
    repo_task = create(:codeql_variant_analysis_repo_task, codeql_variant_analysis: variant_analysis)
    repo_task.status = status
    repo_task.save!
    repo_task
  end

  context "when the workflow run is in progress" do
    CodeqlVariantAnalysisRepoTask::STATUSES.each do |status|
      test "does nothing when the repo task status is #{status}" do
        repo_task = create_repo_task(@in_progress_variant_analysis, status)

        CodeqlVariantAnalysisFinalizerJob.perform_now

        assert_equal status, repo_task.reload.status
        assert_equal 0, GitHub.dogstats.counts("codeql_variant_analysis_finalizer_job.hanging_repo_tasks.count").first.value
      end
    end
  end

  context "when the workflow run is completed" do
    CodeqlVariantAnalysisRepoTask::FINAL_STATUSES.each do |status|
      test "does nothing when the repo task status is #{status}" do
        repo_task = create_repo_task(@completed_variant_analysis, status)

        CodeqlVariantAnalysisFinalizerJob.perform_now

        assert_equal status, repo_task.reload.status
        assert_equal 0, GitHub.dogstats.counts("codeql_variant_analysis_finalizer_job.hanging_repo_tasks.count").first.value
      end
    end

    CodeqlVariantAnalysisRepoTask::NON_FINAL_STATUSES.each do |status|
      test "sets repo task as failed when the repo task status is #{status}" do
        repo_task = create_repo_task(@completed_variant_analysis, status)

        CodeqlVariantAnalysisFinalizerJob.perform_now

        assert_equal "failed", repo_task.reload.status
        assert_equal 1, GitHub.dogstats.counts("codeql_variant_analysis_finalizer_job.hanging_repo_tasks.count").first.value
      end
    end
  end

  test "handles a bunch of variations of repo task and workflow status at once" do
    repo_task_1 = create_repo_task(@in_progress_variant_analysis, "succeeded")
    repo_task_2 = create_repo_task(@in_progress_variant_analysis, "in_progress")
    repo_task_3 = create_repo_task(@completed_variant_analysis, "succeeded")
    repo_task_4 = create_repo_task(@completed_variant_analysis, "in_progress")

    CodeqlVariantAnalysisFinalizerJob.perform_now

    assert_equal "succeeded", repo_task_1.reload.status
    assert_equal "in_progress", repo_task_2.reload.status
    assert_equal "succeeded", repo_task_3.reload.status
    assert_equal "failed", repo_task_4.reload.status
    assert_equal 1, GitHub.dogstats.counts("codeql_variant_analysis_finalizer_job.hanging_repo_tasks.count").first.value
  end
end
