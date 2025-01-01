# typed: strict
# frozen_string_literal: true

class HydroSecretScanningRepositoryDeletedJob < Repositories::RepositoryHydroMessageJob
  extend T::Sig
  include RepositoryHydroMessageJobTenantContext

  queue_as :hydro_secret_scanning_repository_deleted
  retry_on_dirty_exit

  sig { void }
  def perform
    SecretScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: repository_id)
  end

  protected

  sig { override.returns(T::Hash[String, T.untyped]) }
  def logging_context
    super.merge({
      "gh.secret_scanning.source_event": schema,
    })
  end
end
