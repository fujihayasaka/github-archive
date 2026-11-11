# typed: strict
# frozen_string_literal: true

require "resilient/circuit_breaker"

module PullRequests
  module Observability
    class Git
      extend  PullRequests::CircuitBreaker::Git

      sig do
        type_parameters(:T).
        params(
          rpc: Symbol,
          action: T.nilable(Symbol),
          pull_request_id: T.nilable(Integer),
          pull_request_number: T.nilable(Integer),
          repository_id: T.nilable(Integer),
          block: T.proc.returns(T.type_parameter(:T))
        ).returns(T.type_parameter(:T))
      end
      def self.measure(rpc:, action: nil, pull_request_id: nil, pull_request_number: nil, repository_id: nil, &block)
        with_git_circuit_breaker(rpc, repository_id, pull_request_id) do
          start_time = GitHub::Dogstats.monotonic_time
          result = block.call
          duration = GitHub::Dogstats.duration(start_time)

          GitHub.dogstats.distribution(
            "pull_requests.git.duration",
            duration,
            tags: ["rpc:#{rpc}"],
          )

          GitHub.logger.info(
            "gh.git.rpc": rpc,
            "gh.git.action": action,
            "gh.pull_request.id": pull_request_id,
            "gh.pull_request.number": pull_request_number,
            "gh.repo.id": repository_id,
            "gh.git.rpc.duration": duration,
          )

          result
        end
      end

      # Wraps a block of code so that Git RPC metrics emitted while it runs are
      # tagged with the owning pull-requests feature. When the per-repository
      # rollback flag is disabled this is a no-op, so callers can be wired up
      # ahead of broad rollout without changing behavior.
      #
      # The block is always invoked. We push three potential tags into the
      # GitHub.context:
      #   * "feature_owner:pull_requests"
      #   * "feature_name:<feature>"
      #   * "nwo:<repo.nwo>" (only when the monorepo NWO tagging flag is on
      #     for the repository, to keep cardinality bounded to the top monorepos)
      sig do
        type_parameters(:T).
        params(
          repository: T.nilable(::Repository),
          feature: T.any(Symbol, String),
          block: T.proc.returns(T.type_parameter(:T)),
        ).returns(T.type_parameter(:T))
      end
      def self.tag(repository:, feature:, &block)
        unless repository && FeatureFlag.vexi.enabled?(:pull_requests_git_rpc_tagging, repository, default: false)
          return block.call
        end

        tags = [
          "feature_owner:pull_requests",
          "feature_name:#{feature}",
        ]

        if FeatureFlag.vexi.enabled?(:spokesd_spec_tagged_metrics, repository, default: false)
          tags << "nwo:#{repository.name_with_display_owner}"
        end

        existing = GitHub.context[:remote_call_source_datadog_tags] || []
        GitHub.context.push(remote_call_source_datadog_tags: existing + tags)

        begin
          block.call
        ensure
          GitHub.context.pop_key(:remote_call_source_datadog_tags)
        end
      end
    end
  end
end
