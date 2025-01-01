# typed: strict
# frozen_string_literal: true

class HydroSecretScanningRepositoryCreatedJob < Repositories::RepositoryHydroMessageJob
  extend T::Sig
  include GitHub::Memoizer
  include RepositoryHydroMessageJobTenantContext

  queue_as :hydro_secret_scanning_repository_created
  retry_on_dirty_exit

  sig { void }
  def perform
    SecretScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(
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
      "gh.secret_scanning.source_event": schema,
    })
  end
end
