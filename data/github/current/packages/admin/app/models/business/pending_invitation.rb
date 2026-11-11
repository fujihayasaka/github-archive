# typed: true
# frozen_string_literal: true

# An object to be used to represent either OrganizationInvitations or BundledLicenseAssignments
# that are associated with the given Business

class Business::PendingInvitation

  SOURCES = {
    enterprise: "enterprise",
    vss: "vss"
  }

  QUERY_LIMIT = 5000
  TOTAL_ENTRIES_LABEL = "2,000+"

  attr_reader :business, :original_object, :invitee, :email
  attr_accessor :source

  def initialize(business:, original_object:, invitee: nil, email: nil, source: nil)
    @business = business
    @original_object = original_object
    @invitee = invitee
    @email = email
    if source
      @source = source
    elsif original_object.is_a?(Licensing::BundledLicenseAssignment)
      @source = SOURCES[:vss]
    else
      @source = SOURCES[:enterprise]
    end
  end

  def self.max_total_entries
    TOTAL_ENTRIES_LABEL.delete(",").to_i
  end

  def self.from_bundled_license_assignment(bundled_license_assignment)
    Business::PendingInvitation.new(
      business: bundled_license_assignment.business,
      original_object: bundled_license_assignment,
      email: bundled_license_assignment.email
    )
  end

  def self.from_organization_invitation(organization_invitation, source: nil)
    Business::PendingInvitation.new(
      business: organization_invitation.organization.business,
      original_object: organization_invitation,
      invitee: organization_invitation.invitee,
      source: source
    )
  end

  def org_invite?
    original_object.is_a?(OrganizationInvitation)
  end

  def org_invite_invitee_missing?
    original_object.is_a?(OrganizationInvitation) && original_object.email.blank? && original_object.invitee.blank?
  end

  def bundled_license_assignment?
    original_object.is_a?(Licensing::BundledLicenseAssignment)
  end

  # Was this invitation created by a SCIM provisioning request?
  # This is used to determine whether or not to allow editing the invitation outside of the SCIM API.
  # SCIM provisioned invitations have an org invitation to an email & external identity,
  # with no user linked on the invitation.
  def scim_provisioned?
    return false unless @original_object.is_a?(OrganizationInvitation)
    return false unless @original_object.external_identity_id.present?
    return false unless @business.saml_provider&.scim_provisioning_state_enabled?

    # Check if there is a SCIM external identity for the business matching the external identity of the invitation.
    # SCIM provisioned invitations have an external identity ID. Manual invitations do not.
    @business.saml_provider.external_identities.provisioned_by(:scim).find(@original_object.external_identity_id).present?
  end
end
