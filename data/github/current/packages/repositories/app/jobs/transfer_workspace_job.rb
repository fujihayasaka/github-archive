# typed: true
# frozen_string_literal: true

# This job wraps a synchronous call to Repository#transfer_ownership_to
# for Workspace repositories that differs from TransferRepositoryJob:
#
# - Workspace owners do not require notification emails on Transfer complete
# - Workspaces must re-inherit abilities from their parent Repository
#   as an extra step
class TransferWorkspaceJob < ApplicationJob
  queue_as :workspace_repository_abilities

  def perform(workspace_repository_id)
    workspace_repository = Repositories::Public.get_active_or_deleted!(workspace_repository_id)

    return unless workspace_repository.advisory_workspace?

    new_owner = workspace_repository.parent_advisory&.owner

    with_write do
      Ability.throttle do
        workspace_repository.throttle do
          existing_name = workspace_repository.name
          existing_target_repo = Repository.nwo("#{new_owner.login_for_api}/#{existing_name}")

          new_name = nil
          if existing_target_repo
            new_name = Platform::Loaders::NewForkName.load(new_owner, existing_name).sync
          end

          workspace_repository.transfer_ownership_to(new_owner, actor: workspace_repository.owner, new_name:)
        end
      end
    end

    # Re-inherit abilities
    WorkspaceAbilitySetupJob.perform_later(workspace_repository.id, new_owner.id)
  end
end
