# typed: strict
# frozen_string_literal: true

class HydroSecretScanningRepositoryTransferredJob < Repositories::RepositoryHydroMessageJob
  extend T::Sig
  include RepositoryHydroMessageJobTenantContext

  queue_as :hydro_secret_scanning_repository_transferred
  retry_on_dirty_exit

  sig { void }
  def perform
    SecretScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(
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
      "gh.secret_scanning.source_event": schema,
    })
  end
end
