# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers
  include_context "chatops controller"

  let!(:bundler_config) do
    create(:update_config, :active, package_manager: "bundler")
  end

  before do
    travel_to Time.parse("2024-02-15 12:00 +0000").utc
  end

  describe "failed-jobs" do
    let!(:timed_out_job) do
      create(:update_job, :timed_out,
             update_config: bundler_config,
             created_at: "2024-02-10 10:00")
    end
    let!(:errored_job) do
      create(:update_job, :processed_with_errors,
             update_config: bundler_config,
             created_at: "2024-02-10 12:00")
    end

    it "returns job-level metrics in hash-like format" do
      chat "dependabot failed-jobs --from 2024-02-10 09:00 --to 2024-02-10 14:00",
           "user", "#dependabot-ops"

      expect(chatop_response).to include("Failed metrics (UpdateJob#created_at) from 2024-02-10")
      expect(chatop_response).to include("total_failed_jobs:")
      expect(chatop_response).to include("timed_out: 1")
      expect(chatop_response).to include("processed_with_errors: 1")
      expect(chatop_response).to include("failed_jobs_without_pr:")
    end

    context "with state filter" do
      let!(:pr_creation_error) do
        create(:update_job_error,
               update_job: timed_out_job,
               error_type: "pull_request_creation_failure",
               created_at: "2024-02-10 10:05")
      end

      it "filters to only timed_out jobs and includes error breakdown" do
        chat "dependabot failed-jobs --from 2024-02-10 09:00 --to 2024-02-10 14:00 --state timed_out",
             "user", "#dependabot-ops"

        expect(chatop_response).to include("[state: timed_out]")
        expect(chatop_response).to include("total_failed_jobs: 1")
        expect(chatop_response).to include("timed_out: 1")
        expect(chatop_response).not_to include("cancelled:")
        expect(chatop_response).not_to include("processed_with_errors:")
        expect(chatop_response).to include("error_breakdown:")
        expect(chatop_response).to include("pull_request_creation_failure: 1")
      end

      it "rejects invalid states" do
        chat "dependabot failed-jobs --from 2024-02-10 09:00 --to 2024-02-10 14:00 --state invalid",
             "user", "#dependabot-ops"

        expect(chatop_error).to include("Invalid state: invalid")
        expect(chatop_error).to include("Valid states:")
      end
    end

    context "when timestamps are malformed" do
      it "rejects invalid formats" do
        chat "dependabot failed-jobs --from invalid --to 2024-02-10 14:00",
             "user", "#dependabot-ops"

        expect(chatop_error).to include("Invalid date format")
      end
    end

    context "when time range is reversed" do
      it "rejects start after end" do
        chat "dependabot failed-jobs --from 2024-02-10 14:00 --to 2024-02-10 09:00",
             "user", "#dependabot-ops"

        expect(chatop_error).to include("Start time must be before or equal to end time")
      end
    end

    context "when range exceeds allowed window" do
      it "rejects dates beyond one month ago" do
        chat "dependabot failed-jobs --from 2024-01-01 09:00 --to 2024-01-01 14:00",
             "user", "#dependabot-ops"

        expect(chatop_error).to include("Date range must be in the last month")
      end
    end
  end

  describe "failed-repos" do
    let!(:first_repo) { bundler_config.repo }
    let!(:second_account) { create(:account) }
    let!(:second_repo) { create(:repo, account: second_account) }
    let!(:npm_config) do
      create(:update_config, :active, repo: second_repo, package_manager: "npm_and_yarn")
    end

    let!(:first_failure) do
      create(:update_job, :timed_out,
             update_config: bundler_config,
             created_at: "2024-02-10 10:00")
    end
    let!(:second_failure) do
      create(:update_job, :processed_with_errors,
             update_config: npm_config,
             created_at: "2024-02-10 12:00")
    end

    it "returns only repos affected count" do
      chat "dependabot failed-repos --from 2024-02-10 09:00 --to 2024-02-10 14:00",
           "user", "#dependabot-ops"

      expect(chatop_response).to include("Failed repos (UpdateJob#created_at) from 2024-02-10")
      expect(chatop_response).to include("repos_affected: 2")
      expect(chatop_response).not_to include("failed_jobs_by_state")
    end

    context "with state filter" do
      it "filters to only timed_out repos" do
        chat "dependabot failed-repos --from 2024-02-10 09:00 --to 2024-02-10 14:00 --state timed_out",
             "user", "#dependabot-ops"

        expect(chatop_response).to include("[state: timed_out]")
        expect(chatop_response).to include("repos_affected: 1")
      end
    end

    context "when repo query times out" do
      it "returns failure message" do
        allow_any_instance_of(described_class).to receive(:compute_failed_repos_metrics).
          and_raise(ActiveRecord::QueryCanceled.new("Query execution was interrupted"))

        chat "dependabot failed-repos --from 2024-02-10 09:00 --to 2024-02-10 14:00",
             "user", "#dependabot-ops"

        expect(chatop_error).to include("Query timed out")
      end
    end
  end

  describe "failed-accounts" do
    let!(:first_repo) { bundler_config.repo }
    let!(:primary_account) { first_repo.account }
    let!(:secondary_account) { create(:account) }
    let!(:second_repo) { create(:repo, account: secondary_account) }
    let!(:npm_config) do
      create(:update_config, :active, repo: second_repo, package_manager: "npm_and_yarn")
    end

    let!(:first_failure) do
      create(:update_job, :timed_out,
             update_config: bundler_config,
             created_at: "2024-02-10 10:00")
    end
    let!(:second_failure) do
      create(:update_job, :processed_with_errors,
             update_config: npm_config,
             created_at: "2024-02-10 12:00")
    end

    it "returns only accounts affected count" do
      chat "dependabot failed-accounts --from 2024-02-10 09:00 --to 2024-02-10 14:00",
           "user", "#dependabot-ops"

      expect(chatop_response).to include("Failed accounts (UpdateJob#created_at) from 2024-02-10")
      expect(chatop_response).to include("accounts_affected: 2")
      expect(chatop_response).not_to include("failed_jobs_by_state")
      expect(chatop_response).not_to include("repos_affected")
    end

    context "with state filter" do
      it "filters to only timed_out accounts" do
        chat "dependabot failed-accounts --from 2024-02-10 09:00 --to 2024-02-10 14:00 --state timed_out",
             "user", "#dependabot-ops"

        expect(chatop_response).to include("[state: timed_out]")
        expect(chatop_response).to include("accounts_affected: 1")
      end
    end

    context "when account query times out" do
      it "returns failure message" do
        allow_any_instance_of(described_class).to receive(:compute_failed_accounts_metrics).
          and_raise(ActiveRecord::QueryCanceled.new("Query execution was interrupted"))

        chat "dependabot failed-accounts --from 2024-02-10 09:00 --to 2024-02-10 14:00",
             "user", "#dependabot-ops"

        expect(chatop_error).to include("Query timed out")
      end
    end
  end

  describe "failed-errors" do
    let!(:first_repo) { bundler_config.repo }
    let!(:second_repo) do
      account = create(:account)
      create(:repo, account: account)
    end
    let!(:npm_config) do
      create(:update_config, :active, repo: second_repo, package_manager: "npm_and_yarn")
    end

    let!(:job_with_pr_error) do
      create(:update_job, :timed_out,
             update_config: bundler_config,
             created_at: "2024-02-10 10:00")
    end
    let!(:job_with_unknown_error) do
      create(:update_job, :processed_with_errors,
             update_config: npm_config,
             created_at: "2024-02-10 11:00")
    end
    let!(:job_with_timeout_error) do
      create(:update_job, :processed_with_errors,
             update_config: bundler_config,
             created_at: "2024-02-10 12:00")
    end

    before do
      create(:update_job_error,
             update_job: job_with_pr_error,
             error_type: "pull_request_creation_failure",
             created_at: "2024-02-10 10:05")
      create(:update_job_error,
             update_job: job_with_unknown_error,
             error_type: "unknown_error",
             created_at: "2024-02-10 11:05")
      create(:update_job_error,
             update_job: job_with_timeout_error,
             error_type: "timed_out",
             created_at: "2024-02-10 12:05")
    end

    it "returns metrics for a single error type with category" do
      chat "dependabot failed-errors --from 2024-02-10 09:00 --to 2024-02-10 14:00 " \
           "--error-type pull_request_creation_failure",
           "user", "#dependabot-ops"

      expect(chatop_response).to include("Failed errors (UpdateJob#created_at) from 2024-02-10")
      expect(chatop_response).to include("[error_type: pull_request_creation_failure]")
      expect(chatop_response).to include("jobs_affected: 1")
      expect(chatop_response).to include("repos_affected: 1")
      expect(chatop_response).to include("accounts_affected: 1")
      # Should include category for single error type
      expect(chatop_response).to match(/\(.*\)/)
    end

    it "returns metrics for multiple comma-separated error types" do
      chat "dependabot failed-errors --from 2024-02-10 09:00 --to 2024-02-10 14:00 " \
           "--error-type pull_request_creation_failure,unknown_error",
           "user", "#dependabot-ops"

      expect(chatop_response).to include("Failed errors (UpdateJob#created_at) from 2024-02-10")
      expect(chatop_response).to include("[error_type: pull_request_creation_failure, unknown_error]")
      expect(chatop_response).to include("jobs_affected: 2")
      expect(chatop_response).to include("repos_affected: 2")
      expect(chatop_response).to include("accounts_affected: 2")
    end

    it "handles multiple error types separated by commas with spaces" do
      chat "dependabot failed-errors --from 2024-02-10 09:00 --to 2024-02-10 14:00 " \
           "--error-type pull_request_creation_failure, unknown_error, timed_out",
           "user", "#dependabot-ops"

      expect(chatop_response).to include("pull_request_creation_failure, unknown_error, timed_out")
      expect(chatop_response).to include("jobs_affected: 3")
      expect(chatop_response).to include("repos_affected: 2")
      expect(chatop_response).to include("accounts_affected: 2")
    end

    it "requires error-type parameter" do
      chat "dependabot failed-errors --from 2024-02-10 09:00 --to 2024-02-10 14:00",
           "user", "#dependabot-ops"

      expect(chatop_error).to eq("error-type is required")
    end

    context "when no jobs match error types" do
      it "returns zero counts" do
        chat "dependabot failed-errors --from 2024-02-10 09:00 --to 2024-02-10 14:00 " \
             "--error-type nonexistent_error",
             "user", "#dependabot-ops"

        expect(chatop_response).to include("jobs_affected: 0")
        expect(chatop_response).to include("repos_affected: 0")
        expect(chatop_response).to include("accounts_affected: 0")
      end
    end
  end
end
