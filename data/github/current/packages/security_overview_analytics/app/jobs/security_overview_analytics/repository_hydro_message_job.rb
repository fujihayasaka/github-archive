# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class RepositoryHydroMessageJob < ::HydroMessageJob
    extend T::Helpers
    include GitHub::Memoizer
    include LifecycleEventHandler::Hydro
    include LifecycleEventRetryHandler

    abstract!

    retry_on_dirty_exit

    resolve_tenant_context do |message|
      repo_id = message.dig(:repository_id) || message.dig(:repository, :id)
      ::Repositories::Public.resolve_tenant(id: repo_id)
    end

    private

    sig { returns(Integer) }
    memoize def repository_id
      message.dig(:repository, :id) || message.dig(:repository_id)
    end

    sig { returns(::Repository) }
    memoize def repository
      ::Repositories::Public.get_active_or_deleted!(repository_id)
    end

    sig { override.returns(Time) }
    memoize def event_time
      Time.at(timestamp_nano)
    end

    sig { override.returns(String) }
    def source_event
      schema
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.id": repository_id,
        "gh.security_overview_analytics.event_time": event_time,
        "gh.security_overview_analytics.source_event": source_event,
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_log_context
      super.merge({
        app: "github-security-center"
      })
    end
  end
end
