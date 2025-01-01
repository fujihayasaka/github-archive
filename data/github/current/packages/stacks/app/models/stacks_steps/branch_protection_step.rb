# typed: true
# frozen_string_literal: true

module StacksSteps
  class BranchProtectionStep < Step
    def self.validate_inputs(inputs_hash, repo:, actor:, stack_repo: nil)
      method_name = "#{self.class.name}##{__method__}"

      if ConfigValidations::out_of_range?(inputs_hash.dig("required-pull-request-reviews", "required-approving-review-count"), 0, ProtectedBranch::MAX_REQUIRED_APPROVING_REVIEW_COUNT)
        GitHub.dogstats.increment("branch_protection_step.required-approving-review-count", tags: ["action:failed"])
        err_msg = "required-approving-review-count should be between 0 - #{ProtectedBranch::MAX_REQUIRED_APPROVING_REVIEW_COUNT}"
        self.log_validation_error(method_name, err_msg)
        raise Errors::ValidationError.new(err_msg)
      end

      unless repo.can_update_protected_branches?(actor) && repo.plan_supports?(:protected_branches)
        GitHub.dogstats.increment("branch_protection_step.can_update_protected_branch", tags: ["action:failed"])
        err_msg = "Branch Protection Plan not supported in given repository."
        self.log_validation_error(method_name, err_msg)
        raise Errors::ValidationError.new(err_msg)
      end
    end

    def self.get_step_name
      "BranchProtectionStep"
    end

    def get_step_group
      StepGroup.repo_config
    end

    def run(repo:, actor:)
      data = map_inputs_to_data(inputs)
      ref_name = inputs["name"]
      result = BranchProtector.new(repository: repo, actor: actor, ref_name: ref_name, data: data, include_required_signatures: false, entry_point: :stacks_step_protect_branch).protect_branch

      if !result.success?
        GitHub::Logger.log_exception(
          { fn: "#{self.class.name}##{__method__}", repo_id: repo.id }, result.errors)
        raise Errors::BranchProtectionError.new(result.errors.full_messages.to_sentence)
      end
    end

    # Cleans up all the branch protection rules inside a repo.
    def cleanup(repo:, actor:)
      existing_branch_rules = repo.protected_branches
      if existing_branch_rules != nil && existing_branch_rules.any?
        existing_branch_rules.each do |branch_rule|
          branch_rule.destroy
        end
      end
    end

    def self.log_validation_error(method, error_msg)
      GitHub::Logger.log(fn: method,
        message: error_msg)
    end

    private

    def get_required_pull_request_reviews(inputs_hash)
      pull_request_input = inputs_hash["required-pull-request-reviews"]
      return nil if pull_request_input.nil?
      return nil unless pull_request_input.has_key?("dismiss-stale-reviews") \
                  || pull_request_input.has_key?("require-code-owner-reviews") \
                  || pull_request_input.has_key?("required-approving-review-count") \

      required_pull_request_reviews = {}

      if pull_request_input.has_key?("dismiss-stale-reviews")
        required_pull_request_reviews["dismiss_stale_reviews"] = \
          pull_request_input["dismiss-stale-reviews"]
      end

      if pull_request_input.has_key?("require-code-owner-reviews")
        required_pull_request_reviews["require_code_owner_reviews"] = \
          pull_request_input["require-code-owner-reviews"]
      end

      if pull_request_input.has_key?("required-approving-review-count")
        required_pull_request_reviews["required_approving_review_count"] = \
          pull_request_input["required-approving-review-count"]
      end

      required_pull_request_reviews
    end

    def map_inputs_to_data(inputs_hash)
      data = {
        "required_pull_request_reviews" => get_required_pull_request_reviews(inputs_hash)
      }

      if inputs_hash.has_key?("allow-force-pushes")
        data["allow_force_pushes"] = inputs_hash["allow-force-pushes"]
      end

      if inputs_hash.has_key?("allow-deletions")
        data["allow_deletions"] = inputs_hash["allow-deletions"]
      end

      if inputs_hash.has_key?("enforce-admins")
        data["enforce_admins"] = inputs_hash["enforce-admins"]
      end

      data
    end
  end
end
