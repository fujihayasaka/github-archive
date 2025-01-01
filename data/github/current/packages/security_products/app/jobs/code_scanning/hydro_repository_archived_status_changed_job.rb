# typed: strict
# frozen_string_literal: true

module CodeScanning
  class HydroRepositoryArchivedStatusChangedJob < HydroMessageJob
    extend T::Sig
    include GitHub::Memoizer
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_code_scanning_repository_archived_status_changed
    retry_on_dirty_exit

    sig { void }
    def perform
      CodeScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: repository_id)
    end

    sig { override.returns(Integer) }
    memoize def repository_id
      message.dig(:repository_id)
    end

    protected

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.archived": message.dig(:is_archived),
        "gh.code_scanning.source_event": schema,
      })
    end
  end
end
