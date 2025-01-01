# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This should be used when a Repository has been previously enrolled in Dependency Graph services and the data needs
# to be either redetected from source manifest files.
class RepositoryDependencyRedetectJob < ApplicationJob
  queue_as :repository_dependencies
  retry_on_dirty_exit

  def perform(repository_id, actor_id: nil, trigger: :RESET_TRIGGER_UNKNOWN)
    repository = Repositories.domain.by_id(repository_id)
    return false if repository.nil?

    actor = if actor_id
      User.find_by(id: actor_id)
    end

    DependencyGraphPlatform.publish_manifest_reset_event(
      repository: repository,
      actor: actor || User.ghost,
      action: :RESET_ACTION_REDETECT,
      trigger: trigger
    )

    enqueue_legacy_redetection(repository)

    true
  end

  private

  # For DG-API, we reuse the RepositoryDependencyManifestInitializationJob that is normally triggered when
  # DependencyGraph is first enabled on a repository.
  #
  # This is unlikely to change before we deprecate DG-API but any redetections should route via this job
  # to ensure that all services are correctly notified.
  def enqueue_legacy_redetection(repository)
    RepositoryDependencyManifestInitializationJob.perform_later(repository.id)
  end
end
