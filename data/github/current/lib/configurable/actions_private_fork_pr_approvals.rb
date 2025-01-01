# typed: false
# frozen_string_literal: true

module Configurable
  module ActionsPrivateForkPrApprovals

    Error = Class.new(StandardError)

    # Determines which types of users require manual approval for fork pr workflows on private and internal repositories
    # See ActionsForkPrApprovals for public repositories
    KEY = "actions_private_fork_pr_approvals"

    NONE             = "NONE" # Disabled state, no approval required
    READ_ONLY_USERS  = "READ_ONLY_USERS"

    VALUES = [NONE, READ_ONLY_USERS]
    DEFAULT_VALUE = NONE

    def set_actions_private_fork_pr_approvals_policy(policy:, actor:)
      validate_actions_private_fork_pr_approvals_policy!(policy)

      # If the policy is already set on the current entity, skip updates and audit logs
      return if config.get(KEY) == policy && config.local?(KEY)
      config.set(KEY, policy, actor)

      instrument "set_actions_private_fork_pr_approvals_policy", actor: actor, policy: policy
    end

    def actions_private_fork_pr_approvals_policy
      # If the owner is set to the strictest setting, ignore the current policy
      return READ_ONLY_USERS if owner_actions_private_fork_pr_approvals_policy == READ_ONLY_USERS

      policy = config.get(KEY)
      VALUES.include?(policy) ? policy : DEFAULT_VALUE
    end

    def can_disable_actions_private_fork_pr_approvals?
      return false if is_public_repo?

      # Allow disabling if the owner is not on the strictest policy
      owner_actions_private_fork_pr_approvals_policy == NONE
    end

    private

    # This ensures that user-owned repositories will inherit Enterprise settings on GHES
    # The user itself doesn't have any policy
    def effective_actions_private_fork_pr_approvals_configuration_owner
      if configuration_owner.respond_to?(:actions_private_fork_pr_approvals_policy)
        configuration_owner
      elsif configuration_owner&.configuration_owner.respond_to?(:actions_private_fork_pr_approvals_policy)
        configuration_owner.configuration_owner
      end
    end

    def owner_actions_private_fork_pr_approvals_policy
      effective_actions_private_fork_pr_approvals_configuration_owner&.actions_private_fork_pr_approvals_policy || DEFAULT_VALUE
    end

    def validate_actions_private_fork_pr_approvals_policy!(policy)
      if is_public_repo?
        raise Error.new("Actions private fork PR approvals policy not configurable")
      end

      unless VALUES.include?(policy)
        raise Error.new("Invalid Actions private fork PR approvals policy")
      end

      # Don't allow setting to NONE if the owner has a stricter policy
      if policy == NONE && owner_actions_private_fork_pr_approvals_policy == READ_ONLY_USERS
        raise Error.new("Policy is forbidden by entity owner")
      end
    end
  end
end
