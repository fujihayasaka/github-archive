# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class PullRequests::Copilot::BulkGenerateDiffSummaryJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @repository = create(:repository, from_example: :pull_request_source)
    @label = create(:label, repository: @repository, name: "bad thing")
    @pull_request = create(:pull_request, :with_mergeable_head, repository: @repository, labels: [@label])
    @actor = @pull_request.user
  end

  setup do
    PullRequests::Copilot.stubs(:copilot_for_prs_enabled?).returns(true)
    @job_status = Copilot::CompletionJobStatus.create(
      context: {
        repository_id: @repository.id,
        actor_id: @actor.id,
      }
    )
  end

  test "it retries on dirty exit" do
    assert_retry_on_dirty_exit(
      job: PullRequests::Copilot::BulkGenerateDiffSummaryJob,
      args: [job_status_id: @job_status.id]
    )
  end

  context ".enqueue" do
    test "creates a job status and schedules the job" do
      PullRequests::Copilot::BulkGenerateDiffSummaryJob.expects(:perform_later).with do |args|
        status = Copilot::CompletionJobStatus.find!(args[:job_status_id])

        assert_equal @repository.id, status.context[:repository_id]
        assert_equal @actor.id, status.context[:actor_id]
      end

      PullRequests::Copilot::BulkGenerateDiffSummaryJob.enqueue(repository: @repository, actor: @actor, pull_request_ids: [@pull_request.id])
    end
  end

  context "#perform" do
    test "completes GenerateDiffSummaryJob jobs inline and returns the results in the job status context" do
      perform_enqueued_jobs(only: [PullRequests::Copilot::GenerateDiffSummaryJob]) do
        PullRequests::Copilot::Prompt::SummaryPipeline.any_instance.expects(:perform)
        PullRequests::Copilot::Prompt::SummaryPipeline.any_instance.expects(:all_prompts_and_completions).returns(
          [{ prompt: "my prompt", completion: "GPTs response" }]
        )
        PullRequests::Copilot::BulkGenerateDiffSummaryJob.perform_now(job_status_id: @job_status.id, pull_request_ids: [@pull_request.id])

        updated_job_status = Copilot::CompletionJobStatus.find!(@job_status.id)
        assert_predicate updated_job_status, :success?

        assert_equal 1, updated_job_status.context[:total_pull_requests_count]
        assert_equal 1, updated_job_status.context[:pull_requests_completed].size
        assert_equal 0, updated_job_status.context[:pull_requests_in_progress].size
        assert_equal 0, updated_job_status.context[:pull_requests_failed].size

        pr_summary_data = updated_job_status.context[:pull_requests_completed].first
        assert_equal @pull_request.permalink, pr_summary_data[:permalink]
        assert_equal @pull_request.title, pr_summary_data[:title]
        assert_same_elements [@label.name], pr_summary_data[:labels]
        assert_equal [{ prompt: "my prompt", completion: "GPTs response" }], pr_summary_data[:all_prompts_and_completions]
      end
    end

    test "returns data in the job status context about errors from the GenerateDiffSummaryJob run" do
      PullRequests::Copilot::GenerateDiffSummaryJob.expects(:perform_now).raises(StandardError.new("explodifying"))
      PullRequests::Copilot::BulkGenerateDiffSummaryJob.perform_now(job_status_id: @job_status.id, pull_request_ids: [@pull_request.id])

      updated_job_status = Copilot::CompletionJobStatus.find!(@job_status.id)
      assert_predicate updated_job_status, :success?

      assert_equal 1, updated_job_status.context[:total_pull_requests_count]
      assert_equal 0, updated_job_status.context[:pull_requests_completed].size
      assert_equal 0, updated_job_status.context[:pull_requests_in_progress].size
      assert_equal 1, updated_job_status.context[:pull_requests_failed].size

      failed_pr_summary_data = updated_job_status.context[:pull_requests_failed].first
      assert_equal @pull_request.permalink, failed_pr_summary_data[:permalink]
      assert_equal @pull_request.title, failed_pr_summary_data[:title]
      assert_same_elements [@label.name], failed_pr_summary_data[:labels]
      assert_equal "explodifying", failed_pr_summary_data[:error_message]
    end

    test "enqueues a follow-up job for remaining PRs to summarize" do
      pull_request_2 = create(:pull_request, :with_mergeable_head, repository: @repository, labels: [@label])
      pull_request_3 = create(:pull_request, :with_mergeable_head, repository: @repository, labels: [@label])

      perform_enqueued_jobs(only: [PullRequests::Copilot::GenerateDiffSummaryJob, PullRequests::Copilot::BulkGenerateDiffSummaryJob]) do
        PullRequests::Copilot::Prompt::SummaryPipeline.any_instance.expects(:perform).times(3).returns("A PR summary")
        PullRequests::Copilot::BulkGenerateDiffSummaryJob.perform_now(
          job_status_id: @job_status.id,
          pull_request_ids: [@pull_request.id, pull_request_2.id, pull_request_3.id],
          pull_requests_per_job: 1
        )

        # === first enqueued job
        updated_job_status = Copilot::CompletionJobStatus.find!(@job_status.id)
        # only summarized PULL_REQUESTS_PER_JOB x PRs
        assert_equal 1, updated_job_status.context[:total_pull_requests_count]
        # enqueued another PullRequests::Copilot::BulkGenerateDiffSummaryJob for the next batch of PRs
        assert updated_job_status.context[:next_job_status_id], "should create next job and save next job id in context when more prs need to be summarized"

        # === second enqueued job
        next_job_status = Copilot::CompletionJobStatus.find!(updated_job_status.context[:next_job_status_id])
        assert_predicate next_job_status, :success?
        # only summarized PULL_REQUESTS_PER_JOB x PRs
        assert_equal 1, next_job_status.context[:total_pull_requests_count]
        # enqueued another PullRequests::Copilot::BulkGenerateDiffSummaryJob for the next batch of PRs
        assert next_job_status.context[:next_job_status_id], "should create next job and save next job id in context when more prs need to be summarized"


        # === third enqueued job
        next_job_status = Copilot::CompletionJobStatus.find!(next_job_status.context[:next_job_status_id])
        assert_predicate next_job_status, :success?
        # only summarized PULL_REQUESTS_PER_JOB x PRs
        assert_equal 1, next_job_status.context[:total_pull_requests_count]
        # all PRs are summarized, no next PullRequests::Copilot::BulkGenerateDiffSummaryJob enqueued
        refute next_job_status.context[:next_job_status_id], "should not create next job when all PRs have been summarized"
      end
    end
  end
end
