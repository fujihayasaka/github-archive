# frozen_string_literal: true

# "borrowed" from https://github.com/github/meuse/blob/main/lib/active_job/queue_adapters/aqueduct_adapter.rb
module ActiveJob
  module QueueAdapters
    class AqueductAdapter
      def enqueue(job, scheduled_at = nil)
        payload = extract_payload(job)
        DependencyGraph.aqueduct.queue_job(
          queue: job.queue_name,
          payload: payload,
          deliver_at: scheduled_at
        )
      rescue StandardError => e
        Instrument.increment("aqueduct.enqueue.failed", tags: job.stats_tags)
        job.rescue_with_handler(e) || raise
      end

      def enqueue_at(job, scheduled_at)
        enqueue(job, scheduled_at)
      end

      private

      def extract_payload(job)
        JSON.dump(job.serialize)
      end
    end
  end
end
