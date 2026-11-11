# typed: true
# frozen_string_literal: true

class Orgs::People::PendingInvitationToolbarActionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization
  attr_reader :selected_invitations
  attr_reader :invitations_count

  # Get all the IDs of the selected invitations.
  #
  # Returns Array.
  def selected_invitation_ids
    selected_invitations.map(&:id)
  end

  # Public: Should we show the "Remove from organization" button?
  #
  # Returns a boolean.
  def show_remove_button?
    return unless logged_in?
    organization.adminable_by?(current_user)
  end

  def redirect_path
    urls.org_pending_invitations_path(organization)
  end

  def active_failed_invitations
    if defined? @failed_invitations
      return @failed_invitations
    end
    @failed_invitations = organization.active_failed_invitations
  end
end
