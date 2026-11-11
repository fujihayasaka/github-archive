# typed: true
# frozen_string_literal: true

module CodeQuality
  class HydroOrganizationAddPerRepositoryJob < Repositories::RepositoryHydroMessageJob
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_code_quality_organization_add_per_repository
    retry_on_dirty_exit

    sig { void }
    def perform
      return unless FeatureFlag.vexi.enabled?(:code_quality_lifecycle_events_handling, repository, repository.owner, repository.business, default: false)

      CodeQuality::LifecycleHandler.new(repository:, actor_id:).handle_event!
    rescue ActiveRecord::RecordNotFound
      GitHub.logger.info("Skipping CQ enterprise lifecycle processing: repository not found",
        "code.namespace": self.class.name,
        "gh.repo.id": repository_id,
      )
    end
  end
end
