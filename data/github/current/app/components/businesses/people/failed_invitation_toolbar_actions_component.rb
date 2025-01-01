# typed: true
# frozen_string_literal: true

class Businesses::People::FailedInvitationToolbarActionsComponent < ApplicationComponent

  def initialize(business:, selected_invitations:, failed_invitations:)
    @business = business
    @selected_invitations = selected_invitations
    @failed_invitations = failed_invitations
  end

  # Get all the IDs of the selected invitations
  #
  # Returns an array
  def selected_invitation_ids
    @selected_invitations.map(&:id)
  end

  # Public: Should we show the "Delete/retry invitation" button?
  #
  # Returns a boolean.
  def show_delete_retry_invitation_button?
    return unless logged_in?
    @business.adminable_by?(current_user)
  end

end
