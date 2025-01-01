# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class HydroRepositoryDeletedJob < Repositories::RepositoryHydroMessageJob
    include GitHub::Memoizer
    include LifecycleEventHandler
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_security_center_repository_deleted

    retry_on_dirty_exit

    sig { void }
    def perform
      GitHub.logger.info("Purging security center data for repository", "code.namespace": self.class.name, "code.function": __method__)
      with_write do
        RepositorySecurityCenterConfig.throttle do
          RepositorySecurityCenterConfig.where(repository_id:).delete_all
        end
        RepositorySecurityCenterStatus.throttle do
          RepositorySecurityCenterStatus.where(repository_id:).delete_all
        end
        SecurityCenterAlertSeverity.throttle do
          SecurityCenterAlertSeverity.where(repository_id:).delete_all
        end
      end

      GitHub.logger.info("Notifying security features", "code.namespace": self.class.name, "code.function": __method__,)
      SecurityCenterUpdater.notify_security_features_for_repo(repository, source_event: schema)

      instrument_repository_updated
    end

    sig { override.params(error: T.untyped).returns(T::Array[String]) }
    def all_stats_tags(error: $!)
      super(error:).concat([
        "source_event:#{schema}",
      ]).compact
    end

    protected

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.security_center.source_event": schema,
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
