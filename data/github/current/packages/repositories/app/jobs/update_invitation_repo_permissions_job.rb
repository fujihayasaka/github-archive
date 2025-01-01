# typed: true
# frozen_string_literal: true

class UpdateInvitationRepoPermissionsJob < ApplicationJob
  queue_as :update_invitation_repo_permissions

  retry_on_dirty_exit

  def perform(invitation, action:, setter:)
    with_write { invitation.set_permissions(action, setter) }
  end
end
