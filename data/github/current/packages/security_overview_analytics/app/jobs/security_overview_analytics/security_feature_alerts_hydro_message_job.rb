# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class SecurityFeatureAlertsHydroMessageJob < ::HydroMessageJob
    extend T::Helpers
    include GitHub::Memoizer
    include LifecycleEventHandler::Hydro
    include LifecycleEventRetryHandler

    abstract!

    set_callback :perform, :around, :validate_message

    retry_on_dirty_exit

    HYDRO_ERRORS = T.let([
      ::Hydro::Sink::BufferOverflow,
      Kafka::DeliveryFailed
    ], T::Array[T.class_of(StandardError)])
    T.unsafe(self).retry_on(*HYDRO_ERRORS, delay: :polynomially_longer)

    resolve_tenant_context do |message|
      entities = (message[:entities_updated] || []) + (message[:entities_deleted] || [])
      repo_id = entities.map { |e| e.dig(:data, "repository_id") }.compact.first
      ::Repositories::Public.resolve_tenant(id: repo_id)
    end

    private

    sig { params(block: T.proc.void).void }
    def validate_message(&block)
      if entity_type != feature_type
        GitHub.logger.info("Event skipped.", "code.namespace": self.class.name, "code.function": __method__, "gh.security_overview_analytics.reason": "Unexpected entity type.")
        GitHub.dogstats.increment(
          "security_overview_analytics.event.security_feature_alerts_changed.skipped",
          tags: all_stats_tags + ["reason:unexpected_entity_type"]
        )
      else
        yield
      end
    end

    sig { params(alert_payload: T::Hash[String, String]).returns(T::Boolean) }
    def should_handle_alert_event?(alert_payload)
      repository_id = alert_payload["repository_id"]&.to_i || 0
      owner, in_scope = repository_tenant_validation_result[repository_id]
      unless in_scope
        owner_info =
          if owner.is_a? ::Organization
            {
              "gh.org.id": owner.id,
              "gh.org.login": owner.display_login,
            }
          else
            {
              "gh.user.id": owner&.id,
              "gh.user.login": owner&.display_login,
            }
          end

        GitHub.logger.info(
          "Event skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.repo.id": repository_id,
          **owner_info,
          "gh.owner.id": owner&.id,
          "gh.owner.login": owner&.display_login,
          "gh.security_overview_analytics.reason": "Tenant not in scope.",
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.event.security_feature_alerts_changed.skipped",
          tags: all_stats_tags + ["reason:tenant_not_in_scope"]
        )
        return false
      end

      true
    end

    sig { returns(T::Hash[Integer, T.nilable([::User, T::Boolean])]) }
    memoize def repository_tenant_validation_result
      # Following the same pattern as HydroSecurityCenterInsightsEntityBatchJob
      # Some feature type can deliver large batches where could lead to perf issue when not reading repositories/owners in batches.
      repository_ids = updated_alerts.map { |alert| alert["repository_id"] }.uniq
      repository_ids += deleted_alerts.map { |alert| alert["repository_id"] }.uniq

      repository_owner_ids = T.let(repository_ids.uniq.compact.in_groups_of(500, false).flat_map do |batch_ids|
        ::Repository.where(id: batch_ids).pluck(:id, :owner_id)
      end.to_h, T::Hash[Integer, Integer])

      result_by_owner_id = T.let(repository_owner_ids.values.uniq.in_groups_of(500, false).flat_map do |batch_ids|
        ::User.where(id: batch_ids).map do |owner|
          [
            owner.id,
            [owner, should_handle_event_for_owner?(owner)]
          ]
        end
      end.to_h, T::Hash[Integer, [::User, T::Boolean]])

      repository_owner_ids.map { |repo_id, owner_id| [repo_id, result_by_owner_id[owner_id]] }.to_h
    end

    sig { abstract.returns(String) }
    def feature_type; end

    sig { abstract.params(owner: ::User).returns(T::Boolean) }
    def should_handle_event_for_owner?(owner); end

    sig { returns(T::Array[T::Hash[String, String]]) }
    memoize def updated_alerts
      payload = message[:entities_updated]
      return [] if payload.blank?
      payload.map { |m| m[:data] }
    end

    sig { returns(T::Array[T::Hash[String, String]]) }
    memoize def deleted_alerts
      payload = message[:entities_deleted]
      return [] if payload.blank?
      payload.map { |m| m[:data] }
    end

    sig { returns(String) }
    memoize def entity_type
      message[:entity]
    end

    sig { override.returns(Time) }
    memoize def event_time
      Time.at(timestamp_nano)
    end

    sig { override.returns(String) }
    def source_event
      "#{schema}.#{feature_type}"
    end

    sig { returns(Integer) }
    memoize def event_date_id
      Date.id_from_time(event_time)
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.security_overview_analytics.feature_type": feature_type,
        "gh.security_overview_analytics.entity_type": entity_type,
        "gh.security_overview_analytics.event_time": event_time,
        "gh.security_overview_analytics.source_event": schema,
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
