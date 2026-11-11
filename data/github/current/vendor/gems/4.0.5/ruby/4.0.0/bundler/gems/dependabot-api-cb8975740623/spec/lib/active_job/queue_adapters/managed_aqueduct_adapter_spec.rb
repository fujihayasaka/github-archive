# frozen_string_literal: true

require "rails_helper"

class TestJob < ApplicationJob
  queue_as :test_queue

  def perform
    # no-op
  end
end

RSpec.describe ActiveJob::QueueAdapters::ManagedAqueductAdapter do
  let(:aqueduct_adapter) { instance_double(Aqueduct::Rails::ActiveJob::AqueductAdapter) }
  let(:adapter) { described_class.new(aqueduct_adapter: aqueduct_adapter) }

  before do
    allow(aqueduct_adapter).to receive(:enqueue)
    allow(aqueduct_adapter).to receive(:enqueue_at)
  end

  describe "#enqueue" do
    it "sends a job to the aqueduct queue" do
      job = TestJob.new

      adapter.enqueue(job)

      expect(aqueduct_adapter).to have_received(:enqueue).with(job)
    end

    it "reraises the error and increments a metric when the enqueue fails" do
      allow(aqueduct_adapter).to receive(:enqueue).and_raise(StandardError)

      job = TestJob.new

      expect { adapter.enqueue(job) }.to raise_error(StandardError)

      expect(MetricsClient).to have_received(:increment).
        with("job.enqueue_failed",
             tags: {
               job: "test_job",
               error: "standard_error",
               "queue": "test_queue",
             })
    end

    it "retries once when the enqueue fails due to an Aqueduct error" do
      allow(aqueduct_adapter).to receive(:enqueue).and_raise(Aqueduct::Client::ClientError)

      job = TestJob.new

      expect { adapter.enqueue(job) }.to raise_error(Aqueduct::Client::ClientError)

      expect(aqueduct_adapter).to have_received(:enqueue).with(job).twice
      expect(MetricsClient).to have_received(:increment).
        with("job.enqueue_failed",
             tags: {
               job: "test_job",
               error: "aqueduct/client/client_error",
               "queue": "test_queue",
             })
    end
  end

  describe "#enqueue_at" do
    it "sends a job to the aqueduct queue" do
      job = TestJob.new
      scheduled_at = Time.zone.now

      adapter.enqueue_at(job, scheduled_at)

      expect(aqueduct_adapter).to have_received(:enqueue_at).with(job, scheduled_at)
    end

    it "reraises the error and increments a metric when the enqueue_at fails" do
      allow(aqueduct_adapter).to receive(:enqueue_at).and_raise(StandardError)

      job = TestJob.new
      scheduled_at = Time.zone.now

      expect { adapter.enqueue_at(job, scheduled_at) }.to raise_error(StandardError)

      expect(MetricsClient).to have_received(:increment).
        with("job.enqueue_failed",
             tags: {
               job: "test_job",
               error: "standard_error",
               "queue": "test_queue",
             })
    end

    it "retries once when the enqueue fails due to an Aqueduct error" do
      allow(aqueduct_adapter).to receive(:enqueue_at).and_raise(Aqueduct::Client::ClientError)

      job = TestJob.new
      scheduled_at = Time.zone.now

      expect { adapter.enqueue_at(job, scheduled_at) }.to raise_error(Aqueduct::Client::ClientError)

      expect(aqueduct_adapter).to have_received(:enqueue_at).with(job, scheduled_at).twice
      expect(MetricsClient).to have_received(:increment).
        with("job.enqueue_failed",
             tags: {
               job: "test_job",
               error: "aqueduct/client/client_error",
               "queue": "test_queue",
             })
    end
  end
end
