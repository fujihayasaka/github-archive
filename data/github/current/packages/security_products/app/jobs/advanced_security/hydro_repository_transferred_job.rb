# typed: strict
# frozen_string_literal: true

module AdvancedSecurity
  class HydroRepositoryTransferredJob < Repositories::RepositoryHydroMessageJob
    include GitHub::Memoizer
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_advanced_security_repository_transferred

    sig { void }
    def perform
      AdvancedSecurity::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(
        repository_id: repository_id,
        owner_id: message.dig(:new_owner, :id),
        source_event: schema,
        payload: message
      )
    end

    protected

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.owner.id.old": message.dig(:previous_owner, :id),
        "gh.repo.owner.id.new": message.dig(:new_owner, :id),
        "gh.repo.visibility.new": message.dig(:new_visibility),
        "gh.advanced_security.source_event": schema,
      })
    end
  end
end
