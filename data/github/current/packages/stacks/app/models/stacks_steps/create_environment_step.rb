# typed: true
# frozen_string_literal: true

module StacksSteps
  class CreateEnvironmentStep < Step
    def self.validate_inputs(inputs_hash, repo:, actor:, stack_repo: nil)
      method_name = "#{self.class.name}##{__method__}"

      if ConfigValidations::length_out_of_range?(inputs_hash["name"], 1, 255)
        GitHub.dogstats.increment("create_environment_step.name", tags: ["action:failed"])
        err_msg = "Environment name length should not be longer than 255"
        self.log_validation_error(method_name, err_msg)
        raise Errors::ValidationError.new(err_msg)
      end

      if ConfigValidations::environment_branch_invalid?(inputs_hash)
        err_msg = "protected-branches and allowed-branch-rules cannot be set at the same time for environment #{inputs_hash["name"]}"
        self.log_validation_error(method_name, err_msg)
        raise Errors::ValidationError.new(err_msg)
      end

      if ConfigValidations::length_out_of_range?(inputs_hash.dig("reviewers"), 1, Gate::MAX_APPROVERS)
        err_msg = "reviewers count not exceeds max of #{Gate::MAX_APPROVERS} for environment #{inputs_hash["name"]}"
        self.log_validation_error(method_name, err_msg)
        raise Errors::ValidationError.new(err_msg)
      end

      if ConfigValidations::out_of_range?(inputs_hash.dig("wait-timer"), 0, Gate::MAX_TIMEOUT_MINUTES)
        err_msg = "wait-timer for environment #{inputs_hash["name"]} config should be between 0 - #{Gate::MAX_TIMEOUT_MINUTES}"
        self.log_validation_error(method_name, err_msg)
        raise Errors::ValidationError.new(err_msg)
      end
    end

    def self.get_step_name
      "CreateEnvironmentStep"
    end

    def get_step_group
      StepGroup.repo_config
    end

    def run(repo:, actor:)
      inputs_hash = self.inputs
      begin
        data = map_inputs_to_data(inputs_hash)
        environment_name = inputs_hash["name"]
        environment = Environment.create_or_update_environment(repo, data, environment_name)
        configure_custom_branch_policies(environment, inputs_hash, repo)
      # rubocop:todo Lint/GenericRescue
      rescue ActiveRecord::StatementInvalid, Environment::EnvironmentError, StandardError => e
        GitHub::Logger.log_exception(
          { fn: "#{self.class.name}##{__method__}", repo_id: repo.id }, e)
        raise Errors::CreateEnvironmentStepError.new(e.message)
        # rubocop:enable Lint/GenericRescue
      end
    end

    # Cleans up all the environments present inside a repo.
    def cleanup(repo:, actor:)
    end

    def self.log_validation_error(method, error_msg)
      GitHub::Logger.log(fn: method,
        message: error_msg)
    end

    private

    def configure_custom_branch_policies(environment, inputs, repo)
      if environment.repository.can_use_deployment_protected_branch?
        custom_branch_policies = inputs.dig("allowed-branch-rules")

        if custom_branch_policies&.any?
          custom_branch_policies.map do |branch_policy_name|
            branch_policy = environment.branch_policy_gate.branch_policies.build(name: branch_policy_name, repository: repo)
            branch_policy.save
          end
        end
      end
    end

    def map_reviewers(reviewers)
      reviewers.map do |reviewer|
        reviewer_record = reviewer["type"] == "User" ? User.where(login: reviewer["name"]).first : Team.where(name: reviewer["name"]).first
        raise StandardError.new("Invalid reviewer: #{reviewer["name"]}") if reviewer_record.nil?
        {
          "type" => reviewer["type"],
          "id" => reviewer_record["id"]
        }
      end
    end

    def map_inputs_to_data(inputs_hash)
      data = {}

      custom_branch_policies = !!inputs_hash.dig("allowed-branch-rules")&.any?
      protected_branches = !!inputs_hash.dig("protected-branches")

      if custom_branch_policies || protected_branches
        deployment_branch_policy = {
          "protected_branches" => protected_branches,
          "custom_branch_policies" => custom_branch_policies
        }

        data["deployment_branch_policy"] = deployment_branch_policy
      end

      if inputs_hash.key?("reviewers")
        data["reviewers"] = map_reviewers(inputs_hash["reviewers"])
      end

      if inputs_hash.key?("wait-timer")
        data["wait_timer"] = inputs_hash["wait-timer"]
      end

      data
    end
  end
end
