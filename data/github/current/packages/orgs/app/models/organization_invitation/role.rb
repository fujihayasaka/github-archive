# typed: true
# frozen_string_literal: true

# An OrganizationInvitation::Role is a representation of the membership
# abilities a user will have within an organization once they accept a given
# invitation.
#
class OrganizationInvitation::Role < Organization::Role
  attr_reader :invitation

  def initialize(invitation, organization)
    @invitation = invitation
    @member = @invitation.invitee
    @organization = organization
  end

  # Public: Returns the role for a given member off the OrganizationInvitation.
  #
  # Returns a symbol (matching the interface to Organization::Role#type)
  def type
    invitation.role.to_sym
  end
end
