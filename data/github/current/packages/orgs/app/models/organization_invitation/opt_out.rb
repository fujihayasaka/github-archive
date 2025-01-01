# typed: true
# frozen_string_literal: true

class OrganizationInvitation::OptOut < ApplicationRecord::Domain::Users
  belongs_to :organization
  belongs_to :organization_invitation

  validates_length_of :email, within: 3..100, allow_blank: false
  validates_format_of :email,
    with: User::EMAIL_REGEX,
    message: "does not look like an email address",
    allow_blank: false
  validates_presence_of :organization

  # Public: creates an opt out record for the organization/invitation/email
  # combination. This method is idempotent.
  #
  # Returns an Array of OrganizationInvitation::OptOut instances
  def self.opt_out(org:, email: nil, invitee: nil, invitation: nil)
    retry_on_find_or_create_error do
      UserEmail.safe_bulk_normalize(users: invitee, emails: email).map do |email|
        begin
          invitation = T.let(invitation, T.nilable(OrganizationInvitation))
          invitation ||= org.pending_invitation_for(invitee, email: email)

          org.invitation_opt_outs.where(email: email, organization_invitation_id: invitation.try(:id)).first ||
            org.invitation_opt_outs.create(email: email, organization_invitation_id: invitation.try(:id))
        end
      end
      invitation.cancel(actor: invitee) if invitation
      org.invitation_opt_outs.where(organization_invitation_id: invitation.try(:id))
    end
  end

  # Public: Is the invitee (User) or email address opted-out of receiving
  # future invitations from this organization?
  #
  # Returns a boolean
  def self.opted_out?(org:, email: nil, invitee: nil)
    org.invitation_opt_outs.
      where("email IN (?)", UserEmail.safe_bulk_normalize(users: invitee, emails: email)).any?
  end

  # Public: Get a list of opt outs for an organization, grouped by the invitations
  # they are associated with.
  #
  # Returns a Hash of invitation ids, and the opt out records associated with each invitation
  def self.grouped_by_invitation(org:)
    org.invitation_opt_outs.order("created_at DESC").group_by(&:organization_invitation_id)
  end
end
