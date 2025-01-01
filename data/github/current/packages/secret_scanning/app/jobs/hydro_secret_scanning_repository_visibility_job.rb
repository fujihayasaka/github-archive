# typed: true
# frozen_string_literal: true

class HydroSecretScanningRepositoryVisibilityJob < Repositories::RepositoryHydroMessageJob
  include GitHub::Memoizer
  include RepositoryHydroMessageJobTenantContext

  queue_as :hydro_secret_scanning_repository_visibility

  def perform
    if exists_on_disk? && SecretScanning::Features::Repo::PublicScanning.new(repository).enabled?
      # Instrument event in hydro for the moda service to process
      GlobalInstrumenter.instrument("secret_scanning.backfill.repo",
      {
        repository: repository,
        actor: actor,
        owner: repository.owner,
        feature_flags: repository.secret_scanning_post_receive_repo_flags,
        type: :START,
        requested_at: Time.now.utc,
        business: {
          id: repository.owner&.business&.id,
          name: repository.owner&.business&.name,
        },
        wiki_scanning: SecretScanning::Features::Repo::WikiScanning.new(repository).enabled?,
      })
    end

    SecretScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: repository_id)
  end

  private

  memoize def actor
    User.find_by(id: message[:actor_id])
  end

  memoize def exists_on_disk?
    repository.exists_on_disk?
  end

  protected

  def logging_context
    super.merge({
      "gh.repo.visibility.old": message.dig(:old_visibility),
      "gh.repo.visibility.new": message.dig(:new_visibility),
      "gh.secret_scanning.source_event": schema,
    })
  end
end
