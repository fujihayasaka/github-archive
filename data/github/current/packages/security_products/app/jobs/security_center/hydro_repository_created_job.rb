# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/repositories/v1/created_pb"

module SecurityCenter
  class HydroRepositoryCreatedJob < Repositories::RepositoryHydroMessageJob
    extend T::Sig
    include GitHub::Memoizer
    include LifecycleEventHandler
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_security_center_repository_created

    retry_on_dirty_exit

    sig { void }
    def perform
      if repository.deleted?
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:repo_deleted"])
        return
      end

      owner = repository.owner
      if owner.nil?
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:owner_not_found"])
        return
      end

      unless owner.organization? || AdvancedSecurity::Features::User::AdvancedSecurity.new(owner).security_center_for_emus_enabled?
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:owner_not_eligible"])
        return
      end

      GitHub.logger.info("Creating record", "code.namespace": self.class.name, "code.function": __method__)
      # build the payload outside of the write block to avoid inadvertent primary reads for lazy-loaded values
      upsert_payload = {
        repository_id: payload.repository&.id,
        owner_id: payload.repository&.owner_id&.value,
        business_id: repository.business_id,
        owner_type: repository.owner_type,
        name: payload.repository&.name,
        visibility: payload.repository&.visibility.to_s.downcase,
        archived: payload.repository&.is_archived,
        last_push: payload.repository&.pushed_at&.to_time,
        ghas_enabled: false, # there will be a follow-up event to update this
      }
      RepositorySecurityCenterConfig.throttle_writes do
        RepositorySecurityCenterConfig.upsert(upsert_payload, on_duplicate: :skip)
      end

      GitHub.logger.info("Notifying security features", "code.namespace": self.class.name, "code.function": __method__)
      SecurityCenterUpdater.notify_security_features_for_repo(repository, source_event: schema)

      instrument_repository_updated
    end

    sig { override.params(error: T.untyped).returns(T::Array[String]) }
    def all_stats_tags(error: $!)
      super(error:).concat([
        "source_event:#{schema}",
      ]).compact
    end

    private

    sig { returns(::Hydro::Schemas::Github::Repositories::V1::Created) }
    memoize def payload
      ::Hydro::Schemas::Github::Repositories::V1::Created.new(message)
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.owner.id": message.dig(:repository, :owner_id, :value),
        "gh.org.id": message.dig(:repository, :organization_id, :value),
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
