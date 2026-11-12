# frozen_string_literal: true

module RepositoryDependencyUpdate
  class CleanedUpHandler
    class UnexpectedMessageError < StandardError; end

    def self.run(message)
      update = message.value.fetch(:repository_dependency_update)
      repository = message.value.fetch(:repository)

      new(update, repository).run
    end

    def self.dead_letter_errors
      { CleanedUpHandler::UnexpectedMessageError => true }
    end

    def initialize(update, repository)
      @update = update
      @repository = repository
    end

    def run
      validate_message!

      MetricsClient.increment("dependency_update.cleaned_up",
                              tags: message_tags)
    end

    private

    # rubocop:disable Style/GuardClause
    def validate_message!
      unless @update[:error_type] == "dependabot_timed_out"
        raise UnexpectedMessageError,
              "Unexpected error_type: `#{@update[:error_type]}`"
      end

      unless @update[:reason] == :VULNERABILITY
        raise UnexpectedMessageError,
              "Unexpected update reason: `#{@update[:reason]}`"
      end
    end
    # rubocop:enable Style/GuardClause

    def message_tags
      {
        update_job_state: update_job_state,
        update_config_state: update_config_state,
        repository: repo_state,
        pending_pull_request: pending_pull_request?,
        pending_pull_request_state: pending_pull_request_state,
        pull_request: pull_request?,
        package_manager: update_config_package_manager,
        last_update_job_error: last_update_job_error,
        trigger: trigger,
      }
    end

    def update_job_state
      update_job&.current_state || "missing"
    end

    def last_update_job_error
      update_job&.unique_errors&.last&.error_type || "missing"
    end

    def update_job
      return @update_job if defined?(@update_job)

      @update_job = UpdateJob.find_by(github_request_id: @update[:id])
    end

    def repo_state
      return "missing" unless repo

      repo.active? ? "active" : "inactive"
    end

    def repo
      return @repo if defined?(@repo)

      @repo = Repo.find_by(github_id: @repository[:id])
    end

    def update_config_state
      update_job&.update_config&.current_state || "missing"
    end

    def update_config_package_manager
      update_job&.update_config&.package_manager || "unknown"
    end

    def pending_pull_request?
      return false unless update_job

      update_job.pending_pull_requests.any?
    end

    def pending_pull_request_state
      return "missing" unless pending_pull_request?

      update_job.pending_pull_requests.last.current_state
    end

    def pull_request?
      return false unless update_job

      update_job.pull_requests.any?
    end

    def trigger
      @update.fetch(:trigger, :UNKNOWN).to_s.downcase
    end
  end
end
