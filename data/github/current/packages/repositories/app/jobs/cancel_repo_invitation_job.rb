# typed: true
# frozen_string_literal: true

class CancelRepoInvitationJob < ApplicationJob
  queue_as :cancel_repo_invitation

  retry_on_dirty_exit

  def perform(actor:, invitation:, permit_non_repo_admins: false)
    if !permit_non_repo_admins && !invitation.repository.adminable_by?(actor)
      raise RuntimeError.new("actor is not a repo admin")
    end

    with_write do
      invitation.cancel!(actor: actor, force: permit_non_repo_admins)
    end
  end
end
