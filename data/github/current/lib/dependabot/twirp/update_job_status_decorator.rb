# typed: true
# frozen_string_literal: true

module Dependabot
  module Twirp
    class UpdateJobStatusDecorator
      attr_reader :update_job_status

      delegate :id,
               :state,
               :finished_at,
               :errors,
               :update_config_id,
               :actions_external_id,
               :actions_workflow_run_id,
               :runner_type,
               to: :update_job_status

      def initialize(update_job_status)
        @update_job_status = update_job_status
      end

      def to_param
        id
      end

      # TODO: Consider renaming to "primary_error"
      def last_error
        # TODO: Remove reliance on UpdateJobStatus#last_error and use UpdateJobStatus#errors instead
        return update_job_status.last_error if update_job_status.last_error.present?

        errors.last
      end

      def access_recommendation_error?
        errors.any? { |error| error.git_dependencies_not_reachable_error.present? }
      end

      def ecosystem_supports_repository_access?
        update_job_status.package_ecosystem&.is_repository_access_supported
      end

      def unreachable_git_dependency_urls
        errors
          .select { |error| error.git_dependencies_not_reachable_error.present? }
          .map(&:git_dependencies_not_reachable_error)
          .map(&:urls)
          .flatten
      end

      def pretty_state
        case state
        when :PENDING then "Update check pending"
        when :CANCELLED then "Update check cancelled"
        when :ENQUEUED then "Update check enqueued"
        when :PROCESSING then "Update check processing"
        when :PROCESSED then "Update check processed"
        when :PROCESSED_WITH_ERRORS then "Update check processed with errors"
        when :TIMED_OUT then "Update check timed out"
        when :PENDING_RETRY then "Update check pending retry"
        when :NO_SUCCESSFUL_RUNS then "Update check skipped"
        else
          "Unknown"
        end
      end
    end
  end
end
