# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/UsePlatformErrors

module Platform
  module Subscriptions
    class JobStatusUpdated < Platform::Subscriptions::Base
      description "A job status has been updated."
      argument :id, ID, required: true, description: "The ID of the job."
      field :job_status, ::Platform::Objects::JobStatus, "The status object of the job", null: true

      attr_reader :job_status

      def authorized?(**args)
        super
        @job_status = JobStatusSubscription.find(args[:id])
        if @job_status.nil?
          # no permission check needed, since this is returning null
          return true
        end

        unless @job_status.readable_by?(context[:viewer])
          raise GraphQL::ExecutionError, "Subscription halted"
        end

        Helpers::NodeIdentification.typed_object_from_id([Objects::Repository], @job_status.parent_global_relay_id, context)
      rescue Platform::Errors::NotFound
        GitHub.dogstats.increment("graphql_subscriptions.unauthorized", tags: ["event:#{stats_event_name}"])
        raise GraphQL::ExecutionError, "Subscription halted"
      end

      def subscribe(**args)
        { job_status: job_status }
      end

      def update(**args)
        { job_status: job_status }
      end
    end
  end
end
