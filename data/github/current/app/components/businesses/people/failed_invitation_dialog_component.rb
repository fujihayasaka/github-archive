# typed: true
# frozen_string_literal: true

class Businesses::People::FailedInvitationDialogComponent < ApplicationComponent
  include AvatarHelper

  def initialize(business:, redirect_to_path:, selected_invitations:, action_dialog:)
    @business = business
    @redirect_to_path = redirect_to_path
    @selected_invitations = selected_invitations
    @action_dialog = action_dialog
  end

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
    @selected_invitations.map(&:id)
  end
end
