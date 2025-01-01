# typed: true
# frozen_string_literal: true

require "background_job_queues"

# Use Aqueduct client from prod console with:
#
#   require "background_job_queues"
#   c = GitHub::Aqueduct::Client.new(app:"github-production")
module GitHub
  module Aqueduct
    class Client < ::Aqueduct::Client
      attr_accessor :circuit_breaker, :invalid_queues

      def initialize(**kwargs)
        @circuit_breaker = kwargs.delete(:circuit_breaker)

        # Stats for invalid queues if supported on the runtime environment
        @invalid_queues = invalid_queues_for_current_environment

        super
      end

      def send_job(**kwargs)
        if !@invalid_queues.nil? && @invalid_queues.size > 0
          queue = kwargs.fetch(:queue)

          if @invalid_queues.include?(queue)
            # Do not send the job if the queue is invalid
            # and increment the count of invalid queues
            tags = [
              "publishing_app:#{app}",
              "queue:#{queue}",
            ]
            GitHub.dogstats.count("background_jobs.invalid_queue", 1, tags: tags)
            raise GitHub::Aqueduct::Job::InvalidJobQueueError.new("Queue '#{queue}' is not enabled for the current environment, disregarding job.")
          end
        end

        super(**T.unsafe(**kwargs))
      end

      private

      def invalid_queues_for_current_environment
        return @invalid_queues if @invalid_queues.present?

        if GitHub.runtime.enterprise?
          BackgroundJobQueues.invalid_queue_configurations(environment: :enterprise).keys
        else
          []
        end
      end
    end
  end
end
