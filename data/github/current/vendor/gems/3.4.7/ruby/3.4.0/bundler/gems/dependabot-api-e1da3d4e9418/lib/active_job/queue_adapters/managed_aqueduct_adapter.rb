# frozen_string_literal: true

require "active_job"

module ActiveJob
  module QueueAdapters
    # Wrapper class that let's us instrument and retry calls to the aqueduct adapter
    class ManagedAqueductAdapter
      MAX_ENQUEUE_RETRIES = 1

      def self.queue_depth(queue_name)
        Aqueduct::Rails.config.aqueduct_client.queue_depth(queue: queue_name)&.fetch(:depth, 0)
      end

      def initialize(aqueduct_adapter: Aqueduct::Rails::ActiveJob::AqueductAdapter.new)
        @aqueduct_adapter = aqueduct_adapter
      end

      def enqueue(job)
        aqueduct_adapter.enqueue(job)
      rescue Aqueduct::Client::ClientError, Aqueduct::Client::RequestError => e
        retry_count ||= 0
        retry_count += 1
        retry if retry_count <= MAX_ENQUEUE_RETRIES

        instrument_enqueue_error(job, e)
        raise
      rescue Exception => e # rubocop:disable Lint/RescueException
        instrument_enqueue_error(job, e)
        raise
      end

      def enqueue_at(job, scheduled_at)
        aqueduct_adapter.enqueue_at(job, scheduled_at)
      rescue Aqueduct::Client::ClientError, Aqueduct::Client::RequestError => e
        retry_count ||= 0
        retry_count += 1
        retry if retry_count <= MAX_ENQUEUE_RETRIES

        instrument_enqueue_error(job, e)
        raise
      rescue Exception => e # rubocop:disable Lint/RescueException
        instrument_enqueue_error(job, e)
        raise
      end

      private

      attr_reader :aqueduct_adapter

      def instrument_enqueue_error(job, error)
        job_name = job.class.name.underscore
        queue_name = job.queue_name
        error_name = error.class.name.underscore

        MetricsClient.increment("job.enqueue_failed",
                                tags: { job: job_name, queue: queue_name, error: error_name },)
      end
    end
  end
end
