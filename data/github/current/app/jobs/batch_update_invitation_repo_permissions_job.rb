# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Updates org repository invitations permissions/roles and deletes custom role if present and
# has not dependencies
#
# invitations       - Active records of RepositoryInvitation
# action            - The permission to update to. Can be :read, :write, :admin, :triage, :maintain, or a custom role
# setter            - True(default) to update collaborators and False to skip collaborators
# role              - Custom role. default: nil
#
# Returns nothing
class BatchUpdateInvitationRepoPermissionsJob < ApplicationJob
  queue_as :update_invitation_repo_permissions
  retry_on_dirty_exit

  def perform(invitations, action:, setter:, role: nil)
    invitations.each do |invitation|
      ability = invitation.evaluate_ability(action, invitation.repository)
      with_write { invitation.set_permissions(ability, setter) }
    end

    # only delete role after all dependencies are updated
    if !role.nil? && role&.all_dependencies_updated?
      if with_write { role.destroy! }
        GitHub.dogstats.increment("orgs_roles.delete.queued_to_delete", tags: ["status:deleted"])
      end
    end
  end
end
