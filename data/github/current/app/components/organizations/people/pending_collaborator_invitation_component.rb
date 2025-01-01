# typed: true
# frozen_string_literal: true

# A component to handle how we display Invitations to Pending Collaborators
class Organizations::People::PendingCollaboratorInvitationComponent < ApplicationComponent
  include AvatarHelper

  attr_reader :pending_collaborator_invitation,
              :organization,
              :repository

  def initialize(pending_collaborator_invitation:, invitee:, organization:, repository:)
    @pending_collaborator_invitation = pending_collaborator_invitation
    @invitee = invitee
    @organization = organization
    @repository = repository
  end

  # An identifier used to help make lists of this component unique in the DOM
  #
  # Returns a String.
  def dom_id
    "outside-collaborator_#{pending_collaborator_invitation.id}"
  end

  # If the invitation has been sent to an email, return the email as a
  # name, otherwise use the invited user's profile name or login.
  #
  # Returns a String.
  def name_or_login
    email_invitation? ? pending_collaborator : pending_collaborator.safe_profile_name
  end

  # If the invitation is for a user and that user has a profile name attribute, return
  # true. Otherwise return false.
  #
  # Returns a Boolean.
  def profile_name?
    !email_invitation? && pending_collaborator.profile_name.present?
  end

  # If the invitation has been sent to a user, then return the invitee,
  # otherwise return the invitation email.
  #
  # Returns a User or a String.
  def pending_collaborator
    @invitee || pending_collaborator_invitation.email
  end

  # If the invitation was sent to an email, return true, otherwise return false.
  #
  # Returns a Boolean.
  def email_invitation?
    !!pending_collaborator_invitation.email
  end

  # The login of the invitation's organization.
  #
  # Returns a String.
  def organization_login
    organization.display_login
  end

  # The string version of either the invitee or the invitation email for a11y.
  #
  # Returns a String.
  def aria_label
    pending_collaborator.to_s
  end
end
