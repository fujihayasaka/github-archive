# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/repositories/v1/transferred_pb"

module SecurityCenter
  class HydroRepositoryTransferredJob < HydroMessageJob
    extend T::Sig
    include GitHub::Memoizer
    include LifecycleEventHandler
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_security_center_repository_transferred

    retry_on_dirty_exit

    sig { void }
    def perform
      new_owner = ::User.find_by(id: payload.new_owner&.id)
      previous_owner = ::User.find_by(id: payload.previous_owner&.id)

      any_eligible_owner = [new_owner, previous_owner].compact.any? do |owner|
        owner.organization? || AdvancedSecurity::Features::User::AdvancedSecurity.new(owner).security_center_for_emus_enabled?
      end

      # Enqueue for full sync
      if any_eligible_owner
        SecurityCenter::RepositorySyncJob.perform_later(
          repository_id: repository_id,
          source_event: schema,
          event_timestamp: timestamp,
        )
      end

      # Notify security features
      # keeping legacy (non-hydro) event name for compatibility
      GitHub.logger.info("Notifying security features", "code.namespace": self.class.name, "code.function": __method__,)
      SecurityCenterUpdater.notify_security_features_for_repo_id(
        repository_id,
        owner_id: payload.new_owner&.id,
        prev_owner_id: payload.previous_owner&.id,
        source_event: "repo.transfer",
      )

      # NOTE: Do not capture `repository_updated` metric here - we haven't updated the repository yet.
    end

    sig { override.params(error: T.untyped).returns(T::Array[String]) }
    def all_stats_tags(error: $!)
      super(error:).concat([
        "source_event:#{schema}",
      ]).compact
    end

    sig { override.returns(Integer) }
    def repository_id
      payload.repository_id
    end

    private

    sig { returns(::Hydro::Schemas::Github::Repositories::V1::Transferred) }
    memoize def payload
      ::Hydro::Schemas::Github::Repositories::V1::Transferred.new(message)
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.security_center.source_event": schema,
        "gh.repo.id": repository_id,
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
