# typed: strict
# frozen_string_literal: true

module AdvancedSecurity
  class HydroRepositoryRestoredJob < Repositories::RepositoryHydroMessageJob
    extend T::Sig
    include GitHub::Memoizer
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_advanced_security_repository_restored

    sig { void }
    def perform
      AdvancedSecurity::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: repository_id)
    end

    protected

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.advanced_security.source_event": schema,
      })
    end
  end
end
