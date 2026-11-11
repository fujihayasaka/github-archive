# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledJobs::DeleteOldUpdateJobsData do
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
    it "is a noop when there are no update jobs in the database" do
      job.perform_now
      expect(Dependabot::Logger).
        not_to have_received(:info).with(msg: "Deleted old update jobs", ids: anything)
    end

    it "only allows a single job running at a time" do
      allow(Restraint).to receive(:lock!).and_raise(Restraint::UnableToLock, "key")

      expect { job.perform_now }.not_to enqueue_job(described_class)
      expect(Restraint).to have_received(:lock!).with("delete_old_update_jobs_data", 1, 1.minute)
    end

    it "deletes stale completed update jobs" do
      # stale update jobs in terminal states should be deleted
      create_list(:update_job, 2, :processed) { |job| job.update_columns(updated_at: 5.years.ago) }
      create_list(:update_job, 2, :abandoned) { |job| job.update_columns(updated_at: 5.years.ago) }

      # non-completed and non-stale update jobs should not be deleted
      create(:update_job, :pending) { |job| job.update_columns(updated_at: 5.years.ago) }
      create(:update_job, :processed)

      job.perform_now
      expect(UpdateJob.count).to eq 2
    end

    it "deletes dependent: :destroy associated records" do
      create(:update_job, :processed_with_errors) do |job|
        job.update_columns(updated_at: 5.years.ago)
        create(:update_job_warning, update_job: job)
        create(:update_job_unknown_error, update_job: job)
        create(:update_job_error, update_job: job)
      end

      expect { job.perform_now }.
        to change(UpdateJobWarning, :count).by(-1).
        and change(UpdateJobUnknownError, :count).by(-1).
        and change(UpdateJobError, :count).by(-1).
        # pending -> enqueued -> processing -> processed_with_errors
        and change(UpdateJobTransition, :count).by(-3)
    end

    it "performs deletes in batches" do
      job_opts[:write_batch_size] = 1
      create_list(:update_job, 2, :abandoned) { |job| job.update_columns(updated_at: 5.years.ago) }

      expect(Dependabot.freno_throttler).to receive(:throttle).with(Freno::DEPENDABOT_CLUSTER).twice.and_call_original
      job.perform_now
    end

    it "does not delete update jobs that have associated pull requests" do
      update_job = create(:update_job, :processed) { |job| job.update_columns(updated_at: 5.years.ago) }
      create(:pull_request, update_job: update_job)
      expect { job.perform_now }.not_to change(UpdateJob, :count)
    end

    it "does not delete update jobs that within the retention period" do
      create(:update_job, :processed) { |job| job.update_columns(updated_at: 5.months.ago) }
      expect { job.perform_now }.not_to change(UpdateJob, :count)
    end

    it "stops iteration when the first record in a range is newer than the retention period" do
      non_stale_job = create(:update_job, :processed)
      # Pass an offset id and fetch page size that will cause `non_stale_job` to be the
      # only record found in the first call to `fetch_batch`. Since this job is within
      # the retention period, the job should skip further iteration.
      job_opts[:offset_id] = non_stale_job.id - 1
      job_opts[:fetch_page_size] = 1

      # create a stale record that would be deleted if the job did not stop iteration correctly.
      # Verifying that this record is not deleted confirms that the job correctly stopped iteration
      # and did not attempt to delete records with ids greater than the offset_id.
      stale_job = create(:update_job, :processed) { |job| job.update_columns(updated_at: 5.years.ago) }

      # No deletes should happen and no further jobs should be enqueued
      job.perform_now
      expect(described_class).not_to have_been_enqueued
      expect(UpdateJob.exists?(stale_job.id)).to be true
    end

    it "throttles deletes and retries on throttling errors" do
      create(:update_job, :cancelled) { |job| job.update_columns(updated_at: 5.years.ago) }

      allow(Dependabot.freno_throttler).
        to receive(:throttle).
        with(Freno::DEPENDABOT_CLUSTER).
        and_raise(Freno::Throttler::Error)

      expect { job.perform_now }.to enqueue_job(described_class)
    end

    it "enqueues new jobs when there are more records to process" do
      create_list(:update_job, 2, :cancelled) { |job| job.update_columns(updated_at: 5.years.ago) }

      job_opts[:read_batch_size] = 1
      job_opts[:timeout_sec] = 0.0
      freeze_time do
        expect { job.perform_now }.
          to have_enqueued_job(described_class).
          at(described_class::REENQUEUE_DELAY.from_now)
      end
    end

    it "logs metrics about job runs" do
      create(:update_job, :cancelled) { |job| job.update_columns(updated_at: 5.years.ago) }

      prefix = "scheduled_jobs.delete_old_update_jobs_data"
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
