# typed: true
# frozen_string_literal: true

class UpdateInvitationRepoPermissionsJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :update_invitation_repo_permissions

  retry_on_dirty_exit

  def perform(invitation, action:, setter:)
    invitation.set_permissions(action, setter)
  end
end
