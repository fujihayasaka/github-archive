# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/v1/pull_request_merge_pb"

module SecurityOverviewAnalytics
  class HydroPullRequestMergedJob < HydroMessageJob
    extend T::Sig
    include GitHub::Memoizer
    include LifecycleEventRetryHandler

    queue_as :hydro_security_overview_analytics_pull_request_merged

    retry_on_dirty_exit

    resolve_tenant_context do |message|
      repo_id = message.dig(:repository, :id)
      ::Repositories::Public.resolve_tenant(id: repo_id)
    end

    sig { void }
    def perform
      CodeScanningPullRequestAlertsIngestionJob.perform_later(
        pull_request_id: T.must(payload.pull_request&.id),
        source_event:
      )

      GitHub.logger.info("Event processed.", "code.namespace": self.class.name, "code.function": __method__)
      GitHub.dogstats.increment("security_overview_analytics.event.pull_request_merged.processed", tags: all_stats_tags)
    end

    private

    sig { returns(String) }
    def source_event
      schema
    end

    sig { returns(Hydro::Schemas::Github::V1::PullRequestMerge) }
    memoize def payload
      Hydro::Schemas::Github::V1::PullRequestMerge.new(message)
    end

    sig { returns(T.nilable(::Repository)) }
    memoize def repository
      ::Repositories::Public.find_active(T.must(payload.repository&.id))
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.hydro.msg": message.inspect,
        "gh.security_overview_analytics.source_event": source_event
      })
    end
  end
end
