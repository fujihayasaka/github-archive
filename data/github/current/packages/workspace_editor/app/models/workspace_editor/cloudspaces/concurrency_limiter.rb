# typed: strict
# frozen_string_literal: true
module WorkspaceEditor
  module Cloudspaces
    class ConcurrencyLimiter < Codespaces::ConcurrencyPolicy
      include GitHub::Memoizer
      include CloudEnvironments::IConcurrencyLimiter

      sig do
        params(
          user: ::User,
          billable_owner: ::User,
          mutex: T.untyped
        ).void
      end
      def initialize(user, billable_owner:, mutex: nil)
        max_concurrent_instances = Cloudspaces::Dials::MaximumInstancesForUser.new(force_cache_miss: true).value
        mutex ||= GitHub::Redis::ConcurrencySafeMutex.new("codespaces.workspace_editor_cloud_environment_concurrency_policy.#{user.id}", timeout: 5.seconds, wait: 0.5.seconds, sleep: 0.1.seconds)
        super(user, billable_owner: billable_owner, max_concurrent_instances: max_concurrent_instances, mutex: mutex)
      end

      sig { returns(T::Array[Codespace]) }
      memoize def running_codespaces
        user.codespaces.visible_to_workspace_editor_cloud_environments(user, skip_access_check: true).find_all { |c| c.consuming_compute? }
      end

      sig { returns(String) }
      def policy_name
        "copilot_workspace_concurrency_limit"
      end
    end
  end
end
