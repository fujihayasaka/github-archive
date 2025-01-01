# typed: false
# frozen_string_literal: true

module StacksSteps
  class RepoCloneStep < Step
    @@non_retryable_errors = Set.new([Errors::RepositoryNotFound])

    def weight
      @weight ||= StacksSteps::WeightMap::ONE_EIGHTY_SECOND
    end

    def self.get_step_name
      "RepoCloneStep"
    end

    def get_step_group
      StepGroup.repo_cloning
    end

    def self.validate_inputs(inputs, repo:, actor:, stack_repo:)
      method_name = "#{self.class.name}##{__method__}"

      unless inputs.has_key?("ref")
        self.log_and_raise(method_name, "Missing reference of repo to clone from.")
      end

      unless inputs["ref"].is_a?(String)
        self.log_and_raise(method_name, "Invalid reference of repo to clone from.")
      end

      unless stack_repo.resources&.contents&.readable_by?(actor)
        self.log_and_raise(method_name, "Template repository is not readable by cloning user")
      end

      unless stack_repo.active?
        self.log_and_raise(method_name, "#{stack_repo.name_with_owner} is no longer active.")
      end

      if stack_repo.disabled_at.present? || stack_repo.disabled_access_reason
        self.log_and_raise(method_name, "#{stack_repo.name_with_owner} has been disabled and cannot be used as a template.")
      end

    end

    def run(repo:, actor:)
      inputs_hash = self.inputs

      # Fetch previous run's repo clone entry. This is needed because
      # orchestration now supports retries.
      previous_repo_clone_attempt = get_previous_attempt_status
      unless previous_repo_clone_attempt.nil?
        # Skip repo cloning if it passed earlier in a previous plan
        return if repo_clone_successful?(previous_repo_clone_attempt)

        # Raise an error if the clone failed in the previous run
        # TODO: Confirm the proper error string
        GitHub::Logger.error(fn: "#{self.class.name}##{__method__}",
          message: "Repo clone failed in previous run", repo_id: repo.id)
        raise Errors::RepoCloningError.new("Failed to clone the repository.")
      end

      ref = inputs_hash["ref"]
      begin
        elapsed_time = Benchmark.realtime { StacksCloneHelper.new.clone_ref(self.instance, ref) }
        elapsed_time_ms = (elapsed_time * 1000).round
        Metrics.push_metric Metrics::DISTRIBUTION, Component::STEP, "repo_cloning", "time", value: elapsed_time_ms
      rescue => e # rubocop:todo Lint/GenericRescue
        GitHub::Logger.log_exception(
          { fn: "#{self.class.name}##{__method__}", repo_id: repo.id }, e)
        raise Errors::RepoCloningError.new(e.message)
      end
    end

    # We don't support cleanup for a failed repository clone
    def cleanup(repo:, actor:)
    end

    def get_previous_attempt_status
      status_details = self.instance.get_status
      return nil if status_details.failed_step_group.nil?
      status_details
    end

    def repo_clone_successful?(attempt)
      attempt.ran_successfully? || attempt.repo_clone_successful?
    end

    def self.log_and_raise(method, error_msg)
      GitHub::Logger.log(fn: method,
        message: error_msg)
      raise Errors::ValidationError.new(error_msg)
    end
  end
end
