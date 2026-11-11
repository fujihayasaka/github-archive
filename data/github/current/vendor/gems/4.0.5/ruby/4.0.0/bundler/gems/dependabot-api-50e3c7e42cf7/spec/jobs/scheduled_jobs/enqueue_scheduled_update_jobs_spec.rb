# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledJobs::EnqueueScheduledUpdateJobs do
  include ActiveJob::TestHelper

  subject(:job) { described_class }

  let(:account) { create(:account, :active) }
  let(:repo) { create(:repo, account: account) }

  it "only allows a single job running at a time" do
    restraint = Restraint.new
    allow(Restraint).to receive(:new).and_return(restraint)
    allow(restraint).to receive(:lock!).and_raise(Restraint::UnableToLock)

    expect { job.perform_now }.not_to enqueue_job(described_class)
    expect(restraint).to have_received(:lock!).with("enqueue_scheduled_update_jobs", 1, 2.minutes)
  end

  describe "fetch_batch" do
    it "fetches configs with next_enqueue_at in the past" do
      past_config = create(:update_config, :active, repo: repo, directory: "/app1")
      past_config.update_column(:next_enqueue_at, 1.hour.ago)
      future_config = create(:update_config, :active, repo: repo, directory: "/app2")
      future_config.update_column(:next_enqueue_at, 1.hour.from_now)

      job_instance = described_class.new
      batch = job_instance.fetch_batch(offset_id: 0, batch_size: 1000)

      expect(batch).to include(past_config)
      expect(batch).not_to include(future_config)
    end

    it "excludes configs with nil next_enqueue_at" do
      config_with_nil = create(:update_config, :active, repo: repo, directory: "/app1")
      config_with_nil.update_column(:next_enqueue_at, nil)
      config_with_past = create(:update_config, :active, repo: repo, directory: "/app2")
      config_with_past.update_column(:next_enqueue_at, 1.hour.ago)

      job_instance = described_class.new
      batch = job_instance.fetch_batch(offset_id: 0, batch_size: 1000)

      expect(batch).not_to include(config_with_nil)
      expect(batch).to include(config_with_past)
    end

    it "excludes inactive configs" do
      active_config = create(:update_config, :active, repo: repo, directory: "/app1")
      active_config.update_column(:next_enqueue_at, 1.hour.ago)
      deleted_config = create(:update_config, :deleted, repo: repo, directory: "/app2", next_enqueue_at: 1.hour.ago)

      job_instance = described_class.new
      batch = job_instance.fetch_batch(offset_id: 0, batch_size: 1000)

      expect(batch).to include(active_config)
      expect(batch).not_to include(deleted_config)
    end

    it "orders by next_enqueue_at ascending" do
      config2 = create(:update_config, :active, repo: repo, directory: "/app1")
      config2.update_column(:next_enqueue_at, 1.hour.ago)
      config1 = create(:update_config, :active, repo: repo, directory: "/app2")
      config1.update_column(:next_enqueue_at, 2.hours.ago)

      job_instance = described_class.new
      batch = job_instance.fetch_batch(offset_id: 0, batch_size: 1000)

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
      batch = job_instance.fetch_batch(offset_id: 0, batch_size: 2)

      expect(batch.size).to eq(2)
    end
  end

  describe "metrics" do
    it "emits distribution metric" do
      expect(MetricsClient).to receive(:distribution).
        with("enqueue_scheduled_updates_job.dist.time", kind_of(Integer))

      job.perform_now
    end
  end

  describe "process_item" do
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
