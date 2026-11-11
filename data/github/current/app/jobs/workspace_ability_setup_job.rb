# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job sets up the correct abilities on a Workspace repository by copying
# the admin abilities on its parent repository and injecting them directly into
# the Ability table for performance.
#
# This job is used on creation of a workspace repository and after transferring
# ownership of a repository & workspaces to restore the correct abilities
class WorkspaceAbilitySetupJob < ApplicationJob
  queue_as :workspace_repository_abilities
  retry_on_dirty_exit

  def perform(workspace_repository_id, actor_id)
    workspace_repository = Repositories::Public.get_active_or_deleted!(workspace_repository_id)

    return unless workspace_repository.advisory_workspace?

    actor = User.find(actor_id)

    with_write do
      Ability.throttle do
        workspace_repository.throttle do
          RepositoryAdvisory::WorkspaceAbilityManager.new(workspace_repository, actor).perform
        end
      end
    end
  end
end
