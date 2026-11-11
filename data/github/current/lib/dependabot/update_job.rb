# typed: true
# frozen_string_literal: true

module Dependabot
  # Wraps a DependabotApi::v1::UpdateJobStatus object with helper methods
  # that implements the parts of the RepositoryDependencyUpdate
  # interface that relate to job status.
  class UpdateJob
    def self.get_update_job(dependency_update)
      return unless dependency_update

      response = Dependabot::Twirp.update_jobs_client.get_job_status_by_github_request_id(repository_id: dependency_update.repository_id, github_request_id: dependency_update.id)

      return unless response.update_job

      new(response.update_job)
    end

    def initialize(update_job_status)
      @update_job_status = update_job_status
    end

    def state
      @state ||= dependabot_state_to_github_state.to_s
    end

    def error?
      @update_job_status.last_error.present?
    end

    def error_title
      return unless error?

      @update_job_status.last_error.msg
    end

    def error_type
      return unless error?

      @update_job_status.last_error.type
    end

    def error_body
      return unless error?

      @update_job_status.last_error.details
    end

    private

    # Retrieve the equivalent RepositoryDependencyUpdate state or failover
    # to just returning the native Dependabot state if it isn't mapped.
    def dependabot_state_to_github_state
      dependabot_state = @update_job_status.state.downcase

      # This map does not include cancelled or pending_retry presently
      # as it is well understood what state the RSU is likely to be in when these
      # circumstances arise.
      case dependabot_state
      when :pending, :enqueued, :processing
        :requested
      when :processed
        :complete
      when :processed_with_errors, :timed_out, :cancelled
        :error
      else
        dependabot_state
      end
    end
  end
end
