# typed: true
# frozen_string_literal: true

module CodeQuality
  class HydroRepositoryTransferredJob < Repositories::RepositoryHydroMessageJob
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_code_quality_repository_transferred
    retry_on_dirty_exit

    sig { void }
    def perform
      return unless FeatureFlag.vexi.enabled?(:code_quality_lifecycle_events_handling, repository, repository.owner, repository.business, default: false)

      CodeQuality::LifecycleHandler.new(repository:, actor_id:).handle_event!(is_repo_transfer: true)
    rescue ActiveRecord::RecordNotFound
      GitHub.logger.info("Skipping CQ repository transfer processing: repository not found",
        "code.namespace": self.class.name,
        "gh.repo.id": repository_id,
      )
    end
  end
end
