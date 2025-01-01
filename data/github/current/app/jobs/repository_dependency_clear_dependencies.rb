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

    true
  end
end
