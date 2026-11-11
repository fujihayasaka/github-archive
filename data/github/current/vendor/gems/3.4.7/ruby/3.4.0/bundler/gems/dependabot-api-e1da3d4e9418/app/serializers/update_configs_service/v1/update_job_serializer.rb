# frozen_string_literal: true

module UpdateConfigsService
  module V1
    class UpdateJobSerializer < ActiveModel::Serializer
      attributes :status,
                 :trigger_type,
                 :pull_requests

      def status
        job_status_serializer.new(object).to_h
      end

      def trigger_type
        return "SECURITY" if UpdateJob::SECURITY_TRIGGER_TYPES.include?(object.trigger_type)

        return "SCHEDULED" if UpdateJob::SCHEDULED_TRIGGER_TYPES.include?(object.trigger_type)

        return "REBASE" if UpdateJob::REBASE_TRIGGER_TYPES.include?(object.trigger_type)

        return "GRAPH" if UpdateJob::GRAPH_TRIGGER_TYPES.include?(object.trigger_type)

        "UNKNOWN"
      end

      # Returns a sparse hash in case we want to add more rich data later.
      def pull_requests
        if object.updating_a_pull_request?
          [{ github_number: object.pull_request_transition.pull_request.github_number }]
        else
          PullRequest.where(update_job_id: object.id).map do |pr|
            { github_number: pr.github_number }
          end
        end
      end

      private

      def job_status_serializer
        UpdateConfigsService::V1::UpdateJobStatusSerializer
      end
    end
  end
end
