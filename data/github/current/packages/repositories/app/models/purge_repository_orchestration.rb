# typed: false
# frozen_string_literal: true
class PurgeRepositoryOrchestration < RepositoryOrchestration
  step :purgeable? do
    return :skipped, "already purged" if reload_repository.nil?
    return :failed, "not deleted" if !repository.deleted? && repository.active?
    return :failed, "legal hold" if legal_hold?
  end

  job_start

  step :purge_from_disk do
    repository.spokes_api_facade.purge_from_disk!
  end

  step :purge_replicas do
    repository.spokes_api_facade.purge_replicas!
  end

  step :delete_git_backup do
    return if GitHub.enterprise?

    repository.storage_adapter.purge
  end

  step :purge_stars do
    repository.purge_stars unless repository.feature_enabled?(:purge_stars_in_background)
  end

  step :delete_custom_properties do
    # The relationship between repositories and custom properties is one to one right now.
    # Therefore batching is not necessary.
    CustomProperties::Public.destroy_all_properties(repository)
  end

  step :destroy_repository do
    repository&.skip_background_dependent_enqueues = true
    repository&.destroy
  end

  step :publish_purged do
    publish_hydro_event(schema: "github.repositories.v1.Purged")
  end

  step :sync_org_owned_private_network_with_forks do
    network = RepositoryNetwork.find_by(id: network_id)
    network&.sync_org_owned_private_network_with_forks
  end

  step :destroy_packages do
    return if skip_package_destroy_in_repo_purge?

    # If we are going to run out of attempts at deleting packages, just return and move on. This will leave the
    # package records orphaned, but better to do that then fail and leave all the records which are queued for deletion
    # in the following steps orphaned too.
    return if attempts == Orchestration::MAX_ATTEMPTS

    # Destroy all of the package_versions for each package in a repo. Once the last package_version is destroy,
    # the Registry::PackageVersion#destroy_package_if_last_version callback will
    # destroy the corresponding parent Registry::Package
    Registry::Package.where(repository_id: repository_id).select(:id).in_batches do |package_ids|
      Registry::PackageVersion.where(registry_package_id: package_ids).in_batches do |package_version_batch|
        package_version_batch.each do |package_version|
          Registry::PackageVersion.throttle { package_version.destroy }
        end
      end
    end
  end

  step :queue_destroy_jobs do
    repository_ghost = repository || Repository.new(id: repository_id)
    repository_ghost.enqueue_background_dependent_jobs

    DestroyDependentRecordsJob.perform_later(Repository.name, repository_id, :all_hooks) unless repository_ghost.repo_hook_associations_ff?
  end

  def self.job_start_delay
    rand(0..(RepositoryBulkPurgeJob::INTERVAL.seconds * 0.75)).seconds
  end

  def legal_hold?
    ActiveRecord::Base.connected_to(role: :reading) do
      return LegalHold.where(user_id: repository.owner_id).any?
    end
  end

  def reload_repository
    repository = Repository.find_by(id: repository_id)
  end

  def network_id
    data[:network_id]
  end

  def skip_package_destroy_in_repo_purge?
    data[:skip_package_destroy_in_repo_purge]
  end
end
