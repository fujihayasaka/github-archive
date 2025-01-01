# typed: strict
# frozen_string_literal: true

module Codespaces
  class CopilotWorkspaceConcurrencyPolicy < ConcurrencyPolicy
    extend T::Sig
    include GitHub::Memoizer

    sig do
      params(
        user: User,
        billable_owner: User,
        mutex: T.untyped
      ).void
    end
    def initialize(user, billable_owner:, mutex: nil)
      max_concurrent_instances = Codespaces::Dials::MaximumCopilotWorkspaceInstancesForUser.new(force_cache_miss: true).value
      max_concurrent_cores = Codespaces::Dials::MaximumCopilotWorkspaceCoresForUser.new(force_cache_miss: true).value
      mutex ||= GitHub::Redis::ConcurrencySafeMutex.new("codespaces.copilot_workspace_concurrency_policy.#{user.id}", timeout: 5.seconds, wait: 0.5.seconds, sleep: 0.1.seconds)
      super(user, billable_owner: billable_owner, max_concurrent_instances: max_concurrent_instances, max_concurrent_cores: max_concurrent_cores, mutex: mutex)
    end

    sig { returns(T::Array[Codespace]) }
    memoize def running_codespaces
      user.codespaces.visible_to_copilot_workspace(user).find_all { |c| c.consuming_compute? }
    end

    sig { returns(String) }
    def policy_name
      "copilot_workspace_concurrency_policy"
    end

    sig { returns(StandardError) }
    protected def lock_error_exception
      CopilotWorkspaceConcurrencyLimitError.new("You may have too many Copilot Workspaces starting at the same time")
    end
  end
end
