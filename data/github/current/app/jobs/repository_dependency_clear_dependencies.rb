# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This should be used when a Repository has been previously enrolled in Dependency Graph services and the data should
# now be removed, for example due to Dependency Graph being disabled in repository settings.
class RepositoryDependencyClearDependencies < ApplicationJob
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
      action: :RESET_ACTION_CLEAR,
      trigger: trigger
    )

    enqueue_legacy_clear(repository)

    true
  end

  private

  # We use a cross-service job to trigger this event in DG-API. This is unlikely to change before DG-API is deprecated.
  def enqueue_legacy_clear(repository)
    DependencyGraph::CrossServiceJob.enqueue(job_class: "ClearDependenciesJob", args: [repository.id])
  end
end
