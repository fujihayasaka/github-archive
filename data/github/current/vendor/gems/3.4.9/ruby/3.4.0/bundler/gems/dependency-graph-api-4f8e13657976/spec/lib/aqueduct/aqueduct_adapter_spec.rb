# frozen_string_literal: true

require "rails_helper"

describe ActiveJob::QueueAdapters::AqueductAdapter do
  let(:adapter) { described_class.new }
  let(:aqueduct) { instance_double(DependencyGraph::Aqueduct::AqueductConfig) }

  before do
    allow(DependencyGraph).to receive(:aqueduct).and_return(aqueduct)
    allow(aqueduct).to receive(:queue_job)
  end

  describe "#enqueue" do
    context "with a job that specifies custom queue options" do
      let(:job) do
        ClearDependenciesJob.new
      end

      it "merges the queue_options into the queue_job call" do
        adapter.enqueue(job)

        expect(aqueduct).to have_received(:queue_job).with(
          hash_including(redelivery_timeout_secs: 600) # 10 minutes
        )
      end
    end

    context "with a job that doesn't specify custom queue options" do
      # Create a test job class that just uses default queue_options
      class TestJobWithDefaultOptions < RetryJob
        queue_as :test_queue

        def perform
          # no-op
        end
      end

      let(:job) do
        TestJobWithDefaultOptions.new
      end

      it "doesn't include any custom options" do
        adapter.enqueue(job)

        expect(aqueduct).to have_received(:queue_job) do |options|
          # Should only include the standard options - queue, payload, and possibly deliver_at
          standard_keys = [:queue, :payload]
          # Remove deliver_at from consideration if it's nil
          actual_keys = options.keys.reject { |k| k == :deliver_at && options[k].nil? }
          expect(actual_keys).to contain_exactly(*standard_keys)
          expect(options).not_to include(:redelivery_timeout_secs)
        end
      end
    end
  end
end
