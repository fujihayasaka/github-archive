# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledJobs::DeleteOldPullRequestsData do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  subject(:job) { described_class.new(**job_opts) }

  let(:job_opts) { {} }

  before do
    allow(Dependabot::Logger).to receive(:info)
  end

  it "is not enqueued when there is already a job running" do
    Restraint.lock!(described_class::JOB_LOCK_KEY, described_class::CONCURRENT_JOB_COUNT, 1.minute) do
      expect { job.perform_now }.not_to enqueue_job(described_class)
    end
  end

  context "on enterprise", :enterprise do
    it "does not run" do
      expect(Restraint).not_to receive(:lock!)
      expect { job.perform_now }.not_to enqueue_job(described_class)
    end
  end

  context "on proxima", :proxima do
    it "does not run" do
      expect(Restraint).not_to receive(:lock!)
      expect { job.perform_now }.not_to enqueue_job(described_class)
    end
  end

  context "on dotcom", :cloud do
    it "is a noop when there are no PRs in the database" do
      job.perform_now
      expect(Dependabot::Logger).
        not_to have_received(:info).with(msg: "Deleted old pull requests", ids: anything)
    end

    it "only allows a single job running at a time" do
      allow(Restraint).to receive(:lock!).and_raise(Restraint::UnableToLock, "key")

      expect { job.perform_now }.not_to enqueue_job(described_class)
      expect(Restraint).to have_received(:lock!).with("delete_old_pull_requests_data", 1, 1.minute)
    end

    it "deletes stale closed pull requests" do
      # stale closed or merged PRs should be deleted
      create_list(:pull_request, 2, :closed) { |pr| pr.update_columns(updated_at: 5.years.ago) }
      create_list(:pull_request, 2, :merged) { |pr| pr.update_columns(updated_at: 5.years.ago) }

      # non-stale or non-closed PRs should not be deleted
      create(:pull_request, :up_to_date) { |pr| pr.update_columns(updated_at: 5.years.ago) }
      create(:pull_request, :closed)

      job.perform_now
      expect(PullRequest.count).to eq 2
    end

    it "deletes dependent: :destroy associated records" do
      # The factory creates an UpdatedDependency and a PullRequestTransition.
      stale_pr = create(:pull_request, :closed) { |pr| pr.update_columns(updated_at: 5.years.ago) }
      create(:autofix_suggestion_job, pull_request: stale_pr)

      expect { job.perform_now }.
        to change(UpdatedDependency, :count).by(-1).
        and change(AutofixSuggestionJob, :count).by(-1).
        and change(PullRequestTransition, :count).by(-1)
    end

    it "performs deletes in batches" do
      job_opts[:write_batch_size] = 1
      create_list(:pull_request, 2, :closed) { |pr| pr.update_columns(updated_at: 5.years.ago) }

      expect(MetricsClient).to receive(:count).with("scheduled_jobs.delete_old_pull_requests_data.deleted", 1).twice
      job.perform_now
    end

    it "does not delete pull requests within the retention period" do
      create(:pull_request, :closed) { |pr| pr.update_columns(updated_at: 1.year.ago) }

      expect { job.perform_now }.not_to change(PullRequest, :count)
    end

    it "stops iteration when the first record in a range is newer than the retention period" do
      non_stale_pr = create(:pull_request, :closed)
      # Pass an offset id and fetch page size that will cause `non_stale_pr` to be the
      # only record found in the first call to `fetch_batch`. Since this pr is within
      # the retention period, the job should skip further iteration.
      job_opts[:offset_id] = non_stale_pr.id - 1
      job_opts[:fetch_page_size] = 1

      # create a stale record that would be deleted if the job did not stop iteration correctly.
      # Verifying that this record is not deleted confirms that the job correctly stopped iteration
      # and did not attempt to delete records with ids greater than the offset_id.
      stale_pr = create(:pull_request, :closed) { |pr| pr.update_columns(updated_at: 5.years.ago) }

      # No deletes should happen and no further jobs should be enqueued
      job.perform_now
      expect(described_class).not_to have_been_enqueued
      expect(PullRequest.exists?(stale_pr.id)).to be true
    end

    it "throttles deletes and retries throttling errors" do
      create(:pull_request, :closed) { |pr| pr.update_columns(updated_at: 5.years.ago) }

      allow(Dependabot.freno_throttler).
        to receive(:throttle).
        with(Freno::DEPENDABOT_CLUSTER).
        and_raise(Freno::Throttler::Error)

      expect { job.perform_now }.to enqueue_job(described_class)
    end

    it "enqueues new jobs when there are more records to process" do
      create_list(:pull_request, 2, :closed) { |pr| pr.update_columns(updated_at: 5.years.ago) }

      job_opts[:read_batch_size] = 1
      job_opts[:timeout_sec] = 0.0
      freeze_time do
        expect { job.perform_now }.
          to have_enqueued_job(described_class).
          at(described_class::REENQUEUE_DELAY.from_now)
      end
    end

    it "logs metrics about job runs" do
      create(:pull_request, :closed) { |pr| pr.update_columns(updated_at: 5.years.ago) }

      prefix = "scheduled_jobs.delete_old_pull_requests_data"
      expect(MetricsClient).to receive(:gauge).with("#{prefix}.item_id", anything).at_least(:once)
      expect(MetricsClient).
        to receive(:distribution_time).with("#{prefix}.fetch_batch.time").at_least(:once).and_call_original
      expect(MetricsClient).
        to receive(:distribution_time).with("#{prefix}.delete.time").at_least(:once).and_call_original
      expect(MetricsClient).to receive(:count).with("#{prefix}.deleted", anything).at_least(:once)

      job.perform_now
    end
  end
end
