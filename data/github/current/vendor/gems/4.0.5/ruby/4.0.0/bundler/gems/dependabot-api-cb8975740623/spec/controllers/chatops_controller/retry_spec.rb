# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers
  include_context "chatops controller"

  describe "retry" do
    let!(:job) do
      create(:update_job, :processed_with_errors,
             id: 123, github_request_id: 111)
    end

    it "retries update job" do
      expect do
        chat "dependabot retry 123", "user", permitted_slack_room
      end.to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)

      expect(chatop_response).to eq("Enqueued update job retry 123")
    end

    context "with a github_request_id" do
      it "retries update job" do
        expect do
          chat "dependabot retry --github-request-id 111",
               "user",
               permitted_slack_room
        end.to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)

        expect(chatop_response).to eq("Enqueued update job retry 123")
      end
    end

    context "with a job that can't be retried" do
      before { job.transition_to!(:pending_retry) }

      it "explains itself" do
        expect do
          chat "dependabot retry 123", "user", permitted_slack_room
        end.not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)

        expect(chatop_error).to start_with(
          "Job must be processed_with_errors or timed_out"
        )
      end
    end

    context "with a bogus id" do
      it "explains itself" do
        expect do
          chat "dependabot retry 22445", "user", permitted_slack_room
        end.not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)

        expect(chatop_error).to eq("Couldn't find update job 22445.")
      end
    end
  end

  describe "retry_timed_out" do
    let!(:bundler_update_config) do
      create(:update_config, :active,
             package_manager: "bundler")
    end
    let!(:timed_out_job) do
      create(:update_job, :timed_out,
             update_config: bundler_update_config,
             created_at: "2019-10-10 10:10")
    end
    let!(:other_timed_out_job) do
      create(:update_job, :timed_out,
             update_config: bundler_update_config,
             created_at: "2019-10-20 09:20")
    end
    let!(:errored_update_job) do
      create(:update_job, :processed_with_errors,
             update_config: bundler_update_config,
             created_at: "2019-10-10 10:10")
    end

    before do
      travel_to Time.parse("2019-10-30 00:00 +0000").utc
    end

    it "retries timed out update jobs for a package manager" do
      expect do
        chat "dependabot retry-timed-out --from 2019-10-10 09:00 " \
             "--to 2019-10-10T12:00 --package-manager bundler", "user",
             permitted_slack_room
      end.to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
        with(timed_out_job)

      expect(chatop_response).to eq(
        "Retried 1 update jobs created between 2019-10-10T09:00:00+00:00 " \
        "and 2019-10-10T12:00:00+00:00"
      )
    end

    context "when not providing a package manager" do
      let!(:maven_update_job) do
        maven_update_config = create(:update_config, :active,
                                     package_manager: "maven")
        create(:update_job, :timed_out,
               update_config: maven_update_config,
               created_at: "2019-10-10 11:10")
      end

      it "retries timed out update jobs for all package managers" do
        expect do
          chat "dependabot retry-timed-out --from 2019-10-10T09:00 " \
               "--to 2019-10-10T12:00", "user", permitted_slack_room
        end.to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).twice

        expect(chatop_response).to start_with("Retried 2 update jobs")
      end
    end

    context "when too many updates jobs are found to retry" do
      before do
        stub_const("ChatopRetry::MAX_UPDATE_JOBS_TO_RETRY", 1)

        create(:update_job, :timed_out,
               update_config: bundler_update_config,
               created_at: "2019-10-10 11:10")
      end

      it "only retries the max number of update jobs" do
        expect do
          chat "dependabot retry-timed-out --from 2019-10-10T09:00 " \
               "--to 2019-10-10T12:00 --package-manager bundler", "user",
               permitted_slack_room
        end.to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).once

        expect(chatop_response).to start_with(
          "Retried 1 update jobs"
        )
        expect(chatop_response).to include(
          "Didn't get all jobs in the time frame"
        )
      end
    end

    it "only allows retrying up to a month old jobs" do
      expect do
        chat "dependabot retry-timed-out --from 2019-09-10T09:00 " \
             "--to 2019-09-10T12:00", "user", permitted_slack_room
      end.not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)

      expect(chatop_error).to start_with(
        "Date range must be in the last month"
      )
    end

    context "when it's a dry run" do
      it "does not retry update jobs" do
        expect do
          chat "dependabot retry-timed-out --from 2019-10-10T09:00 " \
               "--to 2019-10-10T12:00 --package-manager bundler --dry-run",
               "user", permitted_slack_room
        end.not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)

        expect(chatop_response).to start_with("dry-run: found 1 update jobs")
      end
    end
  end

  describe "retry_processed_with_errors" do
    let!(:bundler_update_config) do
      create(:update_config, :active,
             package_manager: "bundler")
    end
    let!(:processed_with_errors_job) do
      create(:update_job, :processed_with_errors,
             update_config: bundler_update_config,
             created_at: "2019-10-10 10:10")
    end
    let!(:other_processed_with_errors_job) do
      create(:update_job, :processed_with_errors,
             update_config: bundler_update_config,
             created_at: "2019-10-20 09:20")
    end
    let!(:timed_out_update_job) do
      create(:update_job, :timed_out,
             update_config: bundler_update_config,
             created_at: "2019-10-10 10:10")
    end

    before do
      travel_to Time.parse("2019-10-30 00:00 +0000").utc
    end

    it "retries processed with errors update jobs for a package manager" do
      expect do
        chat "dependabot retry-processed-with-errors --from 2019-10-10 09:00 " \
             "--to 2019-10-10T12:00 --package-manager bundler", "user",
             permitted_slack_room
      end.to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
        with(processed_with_errors_job)

      expect(chatop_response).to eq(
        "Retried 1 update jobs created between 2019-10-10T09:00:00+00:00 " \
        "and 2019-10-10T12:00:00+00:00"
      )
    end

    context "when not providing a package manager" do
      let!(:maven_update_job) do
        maven_update_config = create(:update_config, :active,
                                     package_manager: "maven")
        create(:update_job, :processed_with_errors,
               update_config: maven_update_config,
               created_at: "2019-10-10 11:10")
      end

      it "retries processed with errors update jobs for all package managers" do
        expect do
          chat "dependabot retry-processed-with-errors " \
               "--from 2019-10-10T09:00 --to 2019-10-10T12:00",
               "user",
               permitted_slack_room
        end.to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).twice

        expect(chatop_response).to start_with("Retried 2 update jobs")
      end
    end

    context "when too many updates jobs are found to retry" do
      before do
        stub_const("ChatopRetry::MAX_UPDATE_JOBS_TO_RETRY", 1)

        create(:update_job, :processed_with_errors,
               update_config: bundler_update_config,
               created_at: "2019-10-10 11:10")
      end

      it "only retries the max number of update jobs" do
        expect do
          chat "dependabot retry-processed-with-errors " \
               "--from 2019-10-10T09:00 --to 2019-10-10T12:00 " \
               "--package-manager bundler",
               "user",
               permitted_slack_room
        end.to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).once

        expect(chatop_response).to start_with(
          "Retried 1 update jobs"
        )
        expect(chatop_response).to include(
          "Didn't get all jobs in the time frame"
        )
      end
    end

    it "only allows retrying up to a month old jobs" do
      expect do
        chat "dependabot retry-processed-with-errors --from 2019-09-10T09:00 " \
             "--to 2019-09-10T12:00", "user", permitted_slack_room
      end.
        not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).once

      expect(chatop_error).to start_with(
        "Date range must be in the last month"
      )
    end

    context "when it's a dry run" do
      it "does not retry update jobs" do
        expect do
          chat "dependabot retry-processed-with-errors " \
               "--from 2019-10-10T09:00 --to 2019-10-10T12:00 " \
               "--package-manager bundler --dry-run",
               "user",
               permitted_slack_room
        end.
          not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
          once

        expect(chatop_response).to start_with("dry-run: found 1 update jobs")
      end
    end
  end

  describe "retry with error-type filtering" do
    let!(:bundler_update_config) do
      create(:update_config, :active,
             package_manager: "bundler")
    end
    let!(:job_with_pr_error) do
      create(:update_job, :timed_out,
             update_config: bundler_update_config,
             created_at: "2019-10-10 10:10")
    end
    let!(:job_with_unknown_error) do
      create(:update_job, :timed_out,
             update_config: bundler_update_config,
             created_at: "2019-10-10 11:10")
    end
    let!(:job_without_error) do
      create(:update_job, :timed_out,
             update_config: bundler_update_config,
             created_at: "2019-10-10 12:10")
    end

    before do
      travel_to Time.parse("2019-10-30 00:00 +0000").utc

      create(:update_job_error,
             update_job: job_with_pr_error,
             error_type: "pull_request_creation_failure",
             created_at: "2019-10-10 10:15")
      create(:update_job_error,
             update_job: job_with_unknown_error,
             error_type: "unknown_error",
             created_at: "2019-10-10 11:15")
    end

    it "retries only jobs with a single error type" do
      expect do
        chat "dependabot retry-timed-out --from 2019-10-10 09:00 " \
             "--to 2019-10-10 13:00 --package-manager bundler " \
             "--error-type pull_request_creation_failure",
             "user", permitted_slack_room
      end.to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
        with(job_with_pr_error)

      expect(chatop_response).to include(
        "Retried 1 update jobs created between 2019-10-10T09:00:00+00:00 " \
        "and 2019-10-10T13:00:00+00:00 with error-type pull_request_creation_failure"
      )
    end

    it "retries jobs with multiple comma-separated error types" do
      expect do
        chat "dependabot retry-timed-out --from 2019-10-10 09:00 " \
             "--to 2019-10-10 13:00 --package-manager bundler " \
             "--error-type pull_request_creation_failure,unknown_error",
             "user", permitted_slack_room
      end.to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).twice

      expect(chatop_response).to include(
        "Retried 2 update jobs created between 2019-10-10T09:00:00+00:00 " \
        "and 2019-10-10T13:00:00+00:00 with error-type " \
        "pull_request_creation_failure, unknown_error"
      )
    end

    context "with dry-run" do
      it "shows multiple error types in dry-run message" do
        expect do
          chat "dependabot retry-timed-out --from 2019-10-10 09:00 " \
               "--to 2019-10-10 13:00 --package-manager bundler " \
               "--error-type pull_request_creation_failure,unknown_error --dry-run",
               "user", permitted_slack_room
        end.not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)

        expect(chatop_response).to include(
          "dry-run: found 2 update jobs to retry created between " \
          "2019-10-10T09:00:00+00:00 and 2019-10-10T13:00:00+00:00 with error-type " \
          "pull_request_creation_failure, unknown_error"
        )
      end
    end
  end

  private

  def permitted_slack_room
    "#dependabot-ops"
  end
end
