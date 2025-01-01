# typed: strict
# frozen_string_literal: true

module CodeScanning
  class HydroRepositoryVisibilityChangedJob < Repositories::RepositoryHydroMessageJob
    include GitHub::Memoizer
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_code_scanning_repository_visibility_changed
    retry_on_dirty_exit

    sig { void }
    def perform
      CodeScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: repository_id)
    end

    protected

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.visibility.old": message.dig(:old_visibility),
        "gh.repo.visibility.new": message.dig(:new_visibility),
        "gh.code_scanning.source_event": schema,
      })
    end
  end
end
