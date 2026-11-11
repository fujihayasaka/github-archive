# typed: false
# frozen_string_literal: true

module Configurable
  # Typically, workflows are not run from pull requests originating from forks.
  # This is due to security implications if they were to run—fork maintainers
  # would have access to secrets and write tokens of the base repository. Even
  # if we ran by default without write tokens or secrets, fork maintainers
  # would have potentially escalated *read* permissions on things like
  # projects.
  #
  # This module allows administrators to enable this setting anyway manually,
  # and also choose whether secrets and write tokens are sent to those
  # workflows. For organizations that use a fork instead of branching model to
  # work on private repositories, this is generally safe (provided they trust
  # those whom they give access to forking to).
  module ForkPrWorkflowsPolicy
    include Instrumentation::Model

    Error = Class.new(StandardError)

    INSTRUMENTATION_PREFIX = :fork_pr_workflows_policy

    KEY = "fork_pull_request_workflows".freeze

    DISABLED      = 0b000
    RUN_WORKFLOWS = 0b001
    WRITE_TOKENS  = 0b010
    SEND_SECRETS  = 0b100

    RUN_WITH_TOKENS             = RUN_WORKFLOWS | WRITE_TOKENS
    RUN_WITH_SECRETS            = RUN_WORKFLOWS | SEND_SECRETS
    RUN_WITH_TOKENS_AND_SECRETS = RUN_WORKFLOWS | WRITE_TOKENS | SEND_SECRETS

    POLICIES = [DISABLED, RUN_WORKFLOWS, RUN_WITH_TOKENS, RUN_WITH_SECRETS, RUN_WITH_TOKENS_AND_SECRETS].freeze

    # The default policies when this configurable module is not in use.
    PUBLIC_REPO_DEFAULT_POLICY = RUN_WORKFLOWS
    PRIVATE_REPO_DEFAULT_POLICY = DISABLED

    POLICY_NAMES = {
      DISABLED => "DISABLED",
      RUN_WORKFLOWS => "RUN_WORKFLOWS",
      RUN_WITH_TOKENS => "RUN_WITH_TOKENS",
      RUN_WITH_SECRETS => "RUN_WITH_SECRETS",
      RUN_WITH_TOKENS_AND_SECRETS => "RUN_WITH_TOKENS_AND_SECRETS"
    }

    # Public: View a policy formatted as a 3-bit binary literal.
    def self.inspect_policy(policy)
      "0b#{policy.to_s(2).rjust(3, "0")}"
    end

    # Public: Set the entire policy for the entity.
    def set_fork_pr_workflows_policy(policy:, actor:)
      validate_policy!(policy)
      config.set(KEY, policy, actor)
      instrument "set_fork_pr_workflows_policy", actor: actor, policy: POLICY_NAMES.fetch(policy)
    end

    # Public: Determine whether workflows from fork PRs are allowed for this
    # entity.
    #
    # If the entity's owners have this disabled, the highest-level owner takes
    # precedence. Also, a lack of configuration is ignored except for the
    # highest-level owner.
    def can_run_fork_pr_workflows?
      fork_pr_workflows_policy & RUN_WORKFLOWS == RUN_WORKFLOWS
    end

    # Public: Determine whether workflows from fork PRs can be enabled for this
    # entity.
    def can_enable_fork_pr_workflows?
      return false if is_public_repo?

      if configuration_owner.respond_to?(:can_run_fork_pr_workflows?)
        configuration_owner.can_run_fork_pr_workflows?
      else
        true
      end
    end

    # Public: Determine whether sending write tokens to workflows from fork PRs
    # can be enabled for this entity.
    def can_enable_fork_pr_workflows_with_write_tokens?
      return false if is_public_repo?

      if configuration_owner.respond_to?(:can_run_fork_pr_workflows_with_write_tokens?)
        configuration_owner.can_run_fork_pr_workflows_with_write_tokens?
      else
        true
      end
    end

    # Public: Determine whether sending secrets to workflows from fork PRs can
    # be enabled for this entity.
    def can_enable_fork_pr_workflows_with_secrets?
      return false if is_public_repo?

      if configuration_owner.respond_to?(:can_run_fork_pr_workflows_with_secrets?)
        configuration_owner.can_run_fork_pr_workflows_with_secrets?
      else
        true
      end
    end

    # Public: Determine whether write tokens should be sent to workflows from
    # fork PRs.
    def can_run_fork_pr_workflows_with_write_tokens?
      fork_pr_workflows_policy & RUN_WITH_TOKENS == RUN_WITH_TOKENS
    end

    # Public: Determine whether secrets should be sent to workflows from fork
    # PRs.
    def can_run_fork_pr_workflows_with_secrets?
      fork_pr_workflows_policy & RUN_WITH_SECRETS == RUN_WITH_SECRETS
    end

    # Public: Enable running workflows from fork PRs.
    def enable_fork_pr_workflows(actor:)
      set_fork_pr_workflows_policy(policy: RUN_WORKFLOWS, actor: actor)
    end

    # Public: Disable running workflows from fork PRs.
    def disable_fork_pr_workflows(actor:)
      set_fork_pr_workflows_policy(policy: DISABLED, actor: actor)
    end

    # Public: Enable sending write tokens to workflows from fork PRs.
    def enable_fork_pr_workflows_write_tokens(actor:)
      policy = fork_pr_workflows_policy
      set_fork_pr_workflows_policy(policy: policy | WRITE_TOKENS, actor: actor)
    end

    # Public: Disable sending write tokens to workflows from fork PRs.
    def disable_fork_pr_workflows_write_tokens(actor:)
      policy = fork_pr_workflows_policy
      set_fork_pr_workflows_policy(policy: policy & ~WRITE_TOKENS, actor: actor)
    end

    # Public: Enable sending secrets to workflows from fork PRs.
    def enable_fork_pr_workflows_secrets(actor:)
      policy = fork_pr_workflows_policy
      set_fork_pr_workflows_policy(policy: policy | SEND_SECRETS, actor: actor)
    end

    # Public: Disable sending secrets to workflows from fork PRs.
    def disable_fork_pr_workflows_secrets(actor:)
      policy = fork_pr_workflows_policy
      set_fork_pr_workflows_policy(policy: policy & ~SEND_SECRETS, actor: actor)
    end

    # Public: Get the strictest fork PR workflows policy for this entity,
    # taking into account its chain of ownership.
    #
    # This essentially folds over the policies using bitwise AND to end up with
    # the strictest set of defined policies.
    def fork_pr_workflows_policy
      return PUBLIC_REPO_DEFAULT_POLICY if is_public_repo?

      entity_policy = config.int(KEY) || DISABLED

      if configuration_owner_policy
        configuration_owner_policy & entity_policy
      else
        entity_policy
      end
    end

    private

    def is_public_repo?
      is_a?(Repository) && public?
    end

    def configuration_owner_policy
      @configuration_owner_policy ||= configuration_owner.try(:fork_pr_workflows_policy)
    end

    def validate_policy!(policy)
      if is_public_repo?
        raise Error.new("Fork PR workflow policy not configurable")
      end

      unless POLICIES.include?(policy)
        raise Error.new("Invalid fork PR workflows policy")
      end

      if configuration_owner_policy
        if configuration_owner_policy | policy != configuration_owner_policy
          raise Error.new("Policy is forbidden by entity owner")
        end
      end

      policy
    end
  end
end
