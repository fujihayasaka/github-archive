# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/repositories/v1/pushed_pb"

module SecurityCenter
  class HydroRepositoryPushedJob < HydroMessageJob
    include GitHub::Memoizer
    include LifecycleEventHandler
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_security_center_repository_pushed

    retry_on_dirty_exit

    RETRIES = 8
    retry_on SpokesAPI::ResourceExhausted, delay: :polynomially_longer, max_retries: RETRIES

    # Errors that can be logged and ignored.
    IGNORABLE_ERRORS = T.let([
      Errno::ETIMEDOUT,
    ].freeze, T::Array[T::Class[T.anything]])

    sig { void }
    def perform
      if wiki?
        GitHub.dogstats.increment("security_center.event.repository_pushed.skipped", tags: all_stats_tags + ["reason:wiki"])
        return
      end

      repo_actor = FlipperActorAdapters::Repository.new(repository_id)
      unless repo_actor.feature_enabled?(:security_center_skip_dependabot_version_updates_status)
        repository = Repositories::Public.get_active_or_deleted(repository_id)
        pusher = User.find_by_login(payload.pusher)

        if repository && pusher
          payload.ref_updates.each do |hydro_ref_update|
            ref_update = Repositories::RefUpdate.new(
              before: hydro_ref_update.before,
              after: hydro_ref_update.after,
              ref: hydro_ref_update.ref,
              repository: repository,
              pusher: pusher
            )
            next unless ref_update.recordable? && ref_update.default_branch? && ref_update.dependabot_config_changed?

            GlobalInstrumenter.instrument("security_center.dependabot_config_change", {
              repository: repository,
              owner: repository.owner,
            })
            break
          rescue SpokesAPI::ResourceExhausted => e
            raise e unless is_last_retry_of?(e)
          end
        end
      end

      RepositorySecurityCenterConfig.throttle_writes do
        # Using update_all here to generate SQL directly against the DB.
        # This avoids needing to load the record or check for existence.
        RepositorySecurityCenterConfig
          .where(repository_id:)
          .update_all(
            last_push:,
            updated_at: Time.current,
          )
      end

      instrument_repository_updated
    rescue *IGNORABLE_ERRORS => e
      GitHub.logger.warn("Error updating repository last push.", e)
      GitHub.dogstats.increment("security_center.repository_updated.error", tags: all_stats_tags(error: e))
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

    sig { returns(::Hydro::Schemas::Github::Repositories::V1::Pushed) }
    memoize def payload
      ::Hydro::Schemas::Github::Repositories::V1::Pushed.new(message)
    end

    sig { returns(T.nilable(Time)) }
    memoize def last_push
      payload.pushed_at&.to_time
    end

    sig { returns(T::Boolean) }
    def wiki?
      # `path` is the file system path of the git repository
      # wiki repos always end in ".wiki.git"
      # e.g. /data/repositories/7/nw/71/43/b3/32399/2138199.wiki.git
      payload.path.end_with?(".wiki.git")
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.security_center.source_event": schema,
        "gh.repo.id": repository_id,
        "gh.repo.pushed_at": last_push,
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_log_context
      super.merge({
        app: "github-security-center"
      })
    end

    sig { params(exception: StandardError).returns(T::Boolean) }
    def is_last_retry_of?(exception)
      return false unless exception.present?
      (retries(exception) || 0) >= RETRIES
    end
  end
end
