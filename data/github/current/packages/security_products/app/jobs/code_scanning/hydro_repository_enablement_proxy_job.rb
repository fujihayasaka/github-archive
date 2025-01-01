# typed: strict
# frozen_string_literal: true

module CodeScanning
  class HydroRepositoryEnablementProxyJob < HydroMessageJob
    extend T::Sig
    include GitHub::Memoizer
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_code_scanning_repository_enablement_proxy
    retry_on_dirty_exit

    sig { void }
    def perform
      CodeScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(
        repository_id:,
        source_event: schema,
        payload: message
      )
    end

    sig { override.returns(Integer) }
    def repository_id
      message.dig(:repository_id)
    end

    protected

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.code_scanning.repo.enabled": message.dig(:enabled).to_s,
        "gh.code_scanning.source_event": schema,
      })
    end
  end
end
