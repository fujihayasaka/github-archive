# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class RepositoryHydroMessageJob < ::HydroMessageJob
    extend T::Sig
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

    sig { params(feature_to_update: Symbol, feature_enabled_payload: T::Boolean, repository_id: Integer, blk: T.proc.returns(T::Boolean)).void }
    def instrument_incremental_deviation(feature_to_update, feature_enabled_payload, repository_id, &blk)
      if FeatureFlagHelper.incremental_deviation_reporting_enabled?(repository)
        feature_enabled_origin = T.let(false, T::Boolean)
        with_write do
          feature_enabled_origin = yield
        end

        if feature_enabled_payload != feature_enabled_origin
          last_revision = FeatureStatusRevision.where(repository_id:, next_revision_date_id: Date::FUTURE_DATE_ID).first
          if last_revision.present?
            previous_revision_seconds_ago = timestamp - last_revision.updated_at.to_i
          end

          tags = [
            "feature:#{feature_to_update}",
            "feature_enabled_payload:#{feature_enabled_payload}",
            "feature_enabled_origin:#{feature_enabled_origin}",
          ]

          GitHub.logger.info(
            "Feature enablement deviation detected.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_overview_analytics.feature_status_incremental_deviation.feature_enabled_payload": feature_enabled_payload,
            "gh.security_overview_analytics.feature_status_incremental_deviation.feature_enabled_origin": feature_enabled_origin,
            "gh.security_overview_analytics.feature_status_incremental_deviation.previous_revision_seconds_ago": previous_revision_seconds_ago,
            "gh.security_overview_analytics.feature_type": feature_to_update,
          )

          GitHub.dogstats.increment(
            "security_overview_analytics.feature_status.origin_deviation",
            tags:,
          )

          if last_revision.present?
            GitHub.dogstats.distribution(
              "security_overview_analytics.feature_status.origin_deviation.previous_revision_seconds_ago.dist",
              previous_revision_seconds_ago,
              tags:,
            )
          end
        end
      end
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
