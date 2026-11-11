# typed: false
# frozen_string_literal: true

module Configurable
  # This module allows administrators to enable variable sharing setting to
  # wfs from public forks manually.
  # For organizations that use a fork instead of branching model to
  # work on public repositories, this is generally safe (provided they trust
  # those whom they give access to forking to).
  module PublicForkPrWorkflowsPolicy
    include Instrumentation::Model

    Error = Class.new(StandardError)

    INSTRUMENTATION_PREFIX = :public_fork_pr_workflows_policy

    PUBLIC_FORK_KEY = "public_fork_pull_request_workflows".freeze

    INVALID = 0b00
    RUN_WORKFLOWS = 0b01
    SEND_VARIABLES = 0b10

    RUN_WITH_VARIABLES = RUN_WORKFLOWS | SEND_VARIABLES

    PUBLIC_POLICIES = [RUN_WORKFLOWS, RUN_WITH_VARIABLES].freeze

    # The default policies when this configurable module is not in use.
    PUBLIC_REPO_DEFAULT_POLICY = RUN_WORKFLOWS

    POLICY_NAMES = {
      INVALID => "INVALID",
      RUN_WORKFLOWS => "RUN_WORKFLOWS",
      RUN_WITH_VARIABLES => "RUN_WITH_VARIABLES"
    }

    # Public: View a policy formatted as a 3-bit binary literal.
    def self.inspect_policy(policy)
      "0b#{policy.to_s(2).rjust(2, "0")}"
    end

    # Public: Set the entire policy for the entity.
    def set_public_fork_pr_workflows_policy(policy:, actor:)
      if is_private_repo?
        raise Error.new("Fork PR workflow policy not configurable")
      end
      validate_public_policy!(policy)
      config.set(PUBLIC_FORK_KEY, policy, actor)
      instrument "set_public_fork_pr_workflows_policy", actor: actor, policy: POLICY_NAMES.fetch(policy)
    end

    # Public: Determine whether sending variables to workflows from public fork PRs can
    # be enabled for this entity.
    def can_enable_public_fork_pr_workflows_with_variables?
      return false if is_private_repo?

      if configuration_owner.respond_to?(:can_run_public_fork_pr_workflows_with_variables?)
        configuration_owner.can_run_public_fork_pr_workflows_with_variables?
      else
        true
      end
    end

    # Public: Determine whether secrets should be sent to workflows from fork
    # PRs.
    def can_run_public_fork_pr_workflows_with_variables?
      public_fork_pr_workflows_policy & RUN_WITH_VARIABLES == RUN_WITH_VARIABLES
    end

    # Public: Enable sending variables to workflows from fork PRs.
    def enable_public_fork_pr_workflows_variables(actor:)
      policy = public_fork_pr_workflows_policy
      set_public_fork_pr_workflows_policy(policy: policy | SEND_VARIABLES, actor: actor)
    end

    # Public: Disable sending variables to workflows from fork PRs.
    def disable_public_fork_pr_workflows_variables(actor:)
      policy = public_fork_pr_workflows_policy
      set_public_fork_pr_workflows_policy(policy: policy & ~SEND_VARIABLES, actor: actor)
    end

    # Public: Get the strictest public fork PR workflows policy for this entity,
    # taking into account its chain of ownership.
    #
    # This essentially folds over the policies using bitwise AND to end up with
    # the strictest set of defined policies.
    def public_fork_pr_workflows_policy
      return INVALID if is_private_repo?

      entity_policy = config.int(PUBLIC_FORK_KEY) || PUBLIC_REPO_DEFAULT_POLICY
      configuration_owner_public_policy_val = configuration_owner_public_policy
      if configuration_owner_public_policy_val
        configuration_owner_public_policy_val & entity_policy
      else
        entity_policy
      end
    end

    private

    def is_private_repo?
      is_a?(Repository) && private?
    end

    def configuration_owner_public_policy
      @configuration_owner_public_policy ||= configuration_owner.try(:public_fork_pr_workflows_policy)
    end

    def validate_public_policy!(policy)
      if is_private_repo?
        raise Error.new("Fork PR workflow policy not configurable")
      end

      unless PUBLIC_POLICIES.include?(policy)
        raise Error.new("Invalid fork PR workflows policy")
      end

      if configuration_owner_public_policy
        if configuration_owner_public_policy | policy != configuration_owner_public_policy
          raise Error.new("Policy is forbidden by entity owner")
        end
      end

      policy
    end
  end
end
