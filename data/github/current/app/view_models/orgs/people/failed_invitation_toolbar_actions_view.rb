# typed: true
# frozen_string_literal: true

class Orgs::People::FailedInvitationToolbarActionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization
  attr_reader :selected_invitations

  # Get all the IDs of the selected invitations
  #
  # Returns an array
  def selected_invitation_ids
    selected_invitations.map(&:id)
  end

  # Public: Should we show the "Delete invitation" button?
  #
  # Returns a boolean.
  def show_delete_invitations?
    return unless logged_in?
    organization.adminable_by?(current_user)
  end

  def show_retry_invitations?
    return unless logged_in?
    organization.adminable_by?(current_user) && !scim_invitations?
  end

  def scim_invitations?
    selected_invitations.any? do |invitation|
      unless invitation.is_a?(RepositoryInvitation)
        invitation.invitation_source.to_sym == :scim
      end
    end
  end

  def redirect_path
    urls.org_failed_invitations_path(organization)
  end

  def active_failed_invitations_count
    @active_failed_invitations_count ||= organization.active_failed_invitations_count
  end

  def pending_non_manager_invitations
    if defined? @pending_non_manager_invitations
      return @pending_non_manager_invitations
    end
    @pending_non_manager_invitations = organization.pending_non_manager_invitations.
        includes(invitee: :profile)
  end
end
