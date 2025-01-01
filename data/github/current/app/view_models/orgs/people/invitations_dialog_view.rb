# typed: true
# frozen_string_literal: true

class Orgs::People::InvitationsDialogView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization, :redirect_to_path, :selected_invitations, :failed_invitations_count,  :action_dialog

  CONJUGATED_VERB = {
    cancel: {
      present_participle: "Canceling ",
      past: "canceled",
      },
    delete: {
      present_participle: "Deleting ",
      past: "deleted",
      },
    retry: {
      present_participle: "Retrying ",
      past: "retried",
    },
  }

  def selected_invitation_ids
    selected_invitations.map(&:id)
  end

  def scim_invitations?
    selected_invitations.any? do |invitation|
      unless invitation.is_a?(RepositoryInvitation)
        invitation.invitation_source.to_sym == :scim
      end
    end
  end
end
