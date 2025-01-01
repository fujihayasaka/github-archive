# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class OrganizationApplicationAccessRequestedJob < ApplicationJob
  queue_as :organization_application_access_requested
  retry_on_dirty_exit
  discard_on ActiveRecord::RecordNotFound

  resolve_tenant_context do |_, approval_id|
    OauthApplicationApproval.find_by(id: approval_id)&.organization&.business
  end

  def perform(requestor_id, approval_id)
    requestor = User.find(requestor_id)
    approval  = OauthApplicationApproval.includes(:application, :organization).find(approval_id)

    oauth_app    = approval.application
    organization = T.must(approval.organization)

    organization.admins.each do |admin|
      mail = OrganizationMailer.application_access_requested(
        requestor, organization, oauth_app, admin
      )

      mail.deliver_now
    end
  end
end
