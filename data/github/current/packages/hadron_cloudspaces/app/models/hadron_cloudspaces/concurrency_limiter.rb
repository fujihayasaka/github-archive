# typed: strict
# frozen_string_literal: true

module HadronCloudspaces
  class ConcurrencyLimiter < Codespaces::ConcurrencyPolicy
    extend T::Sig
    include GitHub::Memoizer
    include CloudEnvironments::IConcurrencyLimiter

    MAX_CONCURRENT_INSTANCES = 16

    sig do
      params(
        user: User,
        billable_owner: User,
        mutex: T.untyped
      ).void
    end
    def initialize(user, billable_owner:, mutex: nil)
      mutex ||= GitHub::Redis::ConcurrencySafeMutex.new("codespaces.task_cloud_environment_concurrency_policy.#{user.id}", timeout: 5.seconds, wait: 0.5.seconds, sleep: 0.1.seconds)
      super(user, billable_owner: billable_owner, max_concurrent_instances: MAX_CONCURRENT_INSTANCES, mutex: mutex)
    end

    sig { returns(T::Array[Codespace]) }
    memoize def running_codespaces
      user.codespaces.visible_to_task_cloud_environments(user).find_all { |c| c.consuming_compute? }
    end

    sig { returns(String) }
    def policy_name
      "copilot_workspace_concurrency_limit"
    end

    sig { returns(T::Boolean) }
    def raise_lock_error?
      false
    end
  end
end
