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

  def selected_invitation_ids
    @selected_invitations.map(&:id)
  end
end
