# typed: true
# frozen_string_literal: true

class Licensing::Vss::StatusMessage

  EVENT_TYPES = {
    assignment_linked_to_user: "linkedToUser",
    license_revoked: "licenseRevoked",
    pending_account_setup: "pendingAccountSetup",
    linked_to_enterprise_account: "linkedToEnterpriseAccount",
    invited_to_repo: "invitedToRepo",
    invited_to_org: "invitedToOrg",
    declined_repo_invite: "declinedRepoInvite",
    declined_org_invite: "declinedOrgInvite",
  }.freeze

  attr_reader :body

  def initialize(event_type:, assignment:)
    raise ArgumentError.new "#{event_type} is not a valid EVENT_TYPE" unless EVENT_TYPES.keys.include? event_type

    @body = {
      subscriptionGuid: assignment.subscription_id,
      state: EVENT_TYPES[event_type],
      updatedDate: assignment.updated_at,
      enterpriseAgreementNumber: assignment.enterprise_agreement_number,
      email: assignment.email,
    }
  end

  def serialize_message
    body.to_json
  end
end
