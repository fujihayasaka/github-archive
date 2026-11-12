# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledJobs::EnqueueScheduledUpdateJobs do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  subject(:job) { described_class }

  let(:account) { create(:account, :active) }
  let(:repo) { create(:repo, account: account) }

  it "only allows a single job running at a time" do
    allow(Restraint).to receive(:lock!).and_raise(Restraint::UnableToLock.new("key"))

    expect { job.perform_now }.not_to enqueue_job(described_class)
    expect(Restraint).to have_received(:lock!).with("enqueue_scheduled_update_jobs", 1, 2.minutes)
  end

  it "enqueues new jobs when there are more records to process" do
    2.times do |i|
      config = create(:update_config, :active, repo: repo, directory: "/app#{i}")
      config.update_column(:next_enqueue_at, 1.hour.ago)
    end

    freeze_time do
      expect { job.perform_now(timeout_sec: 0.0, batch_size: 1) }.
        to have_enqueued_job(described_class).
        at(described_class::REENQUEUE_DELAY.from_now)
    end
  end

  describe "fetch_batch" do
    it "fetches configs with next_enqueue_at in the past" do
      past_config = create(:update_config, :active, repo: repo, directory: "/app1")
      past_config.update_column(:next_enqueue_at, 1.hour.ago)
      future_config = create(:update_config, :active, repo: repo, directory: "/app2")
      future_config.update_column(:next_enqueue_at, 1.hour.from_now)

      job_instance = described_class.new
      batch = job_instance.fetch_batch(offset_id: 0, batch_size: 1000).flatten

      expect(batch).to include(past_config)
      expect(batch).not_to include(future_config)
    end

    it "excludes configs with nil next_enqueue_at" do
      config_with_nil = create(:update_config, :active, repo: repo, directory: "/app1")
      config_with_nil.update_column(:next_enqueue_at, nil)
      config_with_past = create(:update_config, :active, repo: repo, directory: "/app2")
      config_with_past.update_column(:next_enqueue_at, 1.hour.ago)

      job_instance = described_class.new
      batch = job_instance.fetch_batch(offset_id: 0, batch_size: 1000).flatten

      expect(batch).not_to include(config_with_nil)
      expect(batch).to include(config_with_past)
    end

    it "excludes inactive configs" do
      active_config = create(:update_config, :active, repo: repo, directory: "/app1")
      active_config.update_column(:next_enqueue_at, 1.hour.ago)
      deleted_config = create(:update_config, :deleted, repo: repo, directory: "/app2", next_enqueue_at: 1.hour.ago)

      job_instance = described_class.new
      batch = job_instance.fetch_batch(offset_id: 0, batch_size: 1000).flatten

      expect(batch).to include(active_config)
      expect(batch).not_to include(deleted_config)
    end

    it "orders by next_enqueue_at ascending" do
      config2 = create(:update_config, :active, repo: repo, directory: "/app1")
      config2.update_column(:next_enqueue_at, 1.hour.ago)
      config1 = create(:update_config, :active, repo: repo, directory: "/app2")
      config1.update_column(:next_enqueue_at, 2.hours.ago)

      job_instance = described_class.new
      batch = job_instance.fetch_batch(offset_id: 0, batch_size: 1000).flatten

      # Should be ordered by next_enqueue_at ascending (oldest first)
      next_enqueue_times = batch.map(&:next_enqueue_at)
      expect(next_enqueue_times).to eq(next_enqueue_times.sort)
    end

    it "respects batch_size limit" do
      5.times do |i|
        config = create(:update_config, :active, repo: repo, directory: "/app#{i}")
        config.update_column(:next_enqueue_at, 1.hour.ago)
      end

      job_instance = described_class.new
      batch = job_instance.fetch_batch(offset_id: 0, batch_size: 2).flatten

      expect(batch.size).to eq(2)
    end

    it "returns an array of batches of update configs" do
      configs = Array.new(described_class::ENQUEUE_BATCH_SIZE) do |i|
        config = create(:update_config, :active, repo: repo, directory: "/app#{i}")
        config.update_column(:next_enqueue_at, 1.hour.ago)
        config
      end

      # create an extra matching config to validate multiple enqueue batches
      extra_config = create(:update_config, :active, repo: repo, directory: "/lib")
      extra_config.update_column(:next_enqueue_at, 30.minutes.ago)

      batch = described_class.new.fetch_batch(offset_id: 0)
      expect(batch).to be_an(Array)
      expect(batch).to contain_exactly(configs, [extra_config])
    end
  end

  describe "item_id" do
    it "returns 0" do
      expect(described_class.new.item_id(item: nil)).to eq(0)
    end
  end

  describe "metrics" do
    it "emits enqueued count metric" do
      expect(MetricsClient).to receive(:count).
        with("enqueue_scheduled_updates_job.enqueued.count", kind_of(Integer))

      job.perform_now
    end

    it "emits scheduled lag distribution metric" do
      config = create(:update_config, :active, repo: repo, directory: "/app")
      config.update_column(:next_enqueue_at, 1.hour.ago)

      expect(MetricsClient).to receive(:distribution).
        with("enqueue_scheduled_updates_job.schedule_lag.time", kind_of(Integer))

      job.perform_now
    end
  end

  describe "process_item" do
    it "enqueues CreateScheduledUpdateJob" do
      config = create(:update_config, :active, repo: repo, directory: "/app")
      config.update(next_enqueue_at: 1.hour.ago)

      expect { job.perform_now }.
        to have_enqueued_job(CreateScheduledUpdateJob).
        with(update_config_id: config.id, enqueue_scheduled_update_id: anything)
    end

    context "with config that has next_enqueue_at in the future" do
      before do
        # State machine sets next_enqueue_at to future, which is what we want for this test
        create(:update_config, :active, repo: repo)
      end

      it "does not enqueue CreateScheduledUpdateJob" do
        expect { job.perform_now }.
          not_to have_enqueued_job(CreateScheduledUpdateJob)
      end
    end

    context "with deleted config" do
      before do
        # Deleted configs are excluded regardless of next_enqueue_at
        create(:update_config, :deleted, repo: repo)
      end

      it "does not enqueue CreateScheduledUpdateJob" do
        expect { job.perform_now }.
          not_to have_enqueued_job(CreateScheduledUpdateJob)
      end
    end

    context "with paused repo", feature: :inactivity_pausing do
      before do
        repo.update!(paused_at: 1.minute.ago)
        # Paused repos are excluded regardless of next_enqueue_at
        create(:update_config, :active, repo: repo)
      end

      it "does not enqueue CreateScheduledUpdateJob" do
        expect { job.perform_now }.
          not_to have_enqueued_job(CreateScheduledUpdateJob)
      end
    end

    it "enqueues all jobs in a single call" do
      config = create(:update_config, :active, repo: repo, directory: "/app")
      config.update(next_enqueue_at: 1.hour.ago)

      expect(ActiveJob).to receive(:perform_all_later) do |jobs|
        expect(jobs.length).to eq(1)
        expect(jobs[0]).to be_a(CreateScheduledUpdateJob)
        expect(jobs[0].arguments[0]).to include(update_config_id: config.id)
        jobs.each { |job| job.successfully_enqueued = true }
      end

      job.perform_now
    end

    it "does not update next_enqueue_at on a job if enqueueing that job fails" do
      enqueue_at = nil
      freeze_time do
        enqueue_at = 1.hour.ago
        Array.new(2) do |i|
          config = create(:update_config, :active, repo: repo, directory: "/app/#{i}")
          config.update(next_enqueue_at: enqueue_at)
          config
        end
      end

      allow(ActiveJob).to receive(:perform_all_later) do |jobs|
        jobs[0].successfully_enqueued = true
        jobs[1].successfully_enqueued = false
      end

      # Set the timeout to 0 to force the job to process only one config batch
      # and then exit.  This allows us to test out the behavior when some jobs
      # in a batch fail to enqueue without relying on test timing.
      expect { job.perform_now(timeout_sec: 0.0) }.
        # changes by -1 instead of -2 since only one job was successfully enqueued
        to change { UpdateConfig.where(next_enqueue_at: enqueue_at).count }.by(-1)
    end
  end

  describe "error handling" do
    it "logs error and re-raises on failure" do
      allow(described_class).to receive(:new).and_raise(StandardError.new("test error"))

      expect { job.perform_now }.to raise_error(StandardError, "test error")
    end
  end

  describe "update_next_enqueue_at" do
    context "with a valid cron expression" do
      let(:cron_expression) { "0 10 * * 1 UTC" } # Every Monday at 9am

      it "updates next_enqueue_at to the next scheduled time" do
        update_config = create(:update_config, :active, repo: repo,
                                                        update_schedule_cron_expression: cron_expression)
        # Set to past so it gets picked up by fetch_batch
        update_config.update_column(:next_enqueue_at, 1.hour.ago)
        original_next_enqueue_at = update_config.next_enqueue_at

        job.perform_now

        update_config.reload
        expect(update_config.next_enqueue_at).to be > Time.current.utc
        expect(update_config.next_enqueue_at).not_to eq(original_next_enqueue_at)
      end

      context "with a nil cron expression and scheduled update" do
        it "sets the cron expression and next_enqueue_at" do
          update_config = create(:update_config, :active, repo: repo,
                                                          update_schedule: "daily",
                                                          update_schedule_time_of_day: "09:00",
                                                          update_schedule_cron_expression: nil)
          # Set to past so it gets picked up by fetch_batch
          update_config.update_column(:next_enqueue_at, 1.hour.ago)

          job.perform_now

          update_config.reload
          expect(update_config.update_schedule_cron_expression).to eq("0 9 * * 1-5 UTC")
          expect(update_config.next_enqueue_at).to be > Time.current.utc
        end
      end
    end
  end
end
