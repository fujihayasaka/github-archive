# typed: strict
# frozen_string_literal: true

module CodeScanning
  class HydroRepositoryCreatedJob < Repositories::RepositoryHydroMessageJob
    extend T::Sig
    include GitHub::Memoizer
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_code_scanning_repository_created
    retry_on_dirty_exit

    sig { void }
    def perform
      CodeScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(
        repository_id: repository_id,
        owner_id: owner_id
      )
    end

    protected

    sig { returns(Integer) }
    memoize def owner_id
      message.dig(:repository, :owner_id, :value)
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.owner.id": message.dig(:repository, :owner_id, :value),
        "gh.org.id": message.dig(:repository, :organization_id, :value),
        "gh.is.fork": message.dig(:repository, :is_fork),
        "gh.code_scanning.source_event": schema,
      })
    end
  end
end
