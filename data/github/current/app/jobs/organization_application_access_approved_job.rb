# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class OrganizationApplicationAccessApprovedJob < ApplicationJob
  queue_as :organization_application_access_approved

  BATCH_SIZE = 1000

  discard_on ActiveRecord::RecordNotFound

  retry_on_dirty_exit

  resolve_tenant_context do |approval_id, _|
    OauthApplicationApproval.find_by(id: approval_id)&.organization&.business
  end


  def perform(approval_id, approver_id)
    approval = OauthApplicationApproval.includes(:application, :organization).find(approval_id)

    application  = T.must(approval.application)
    organization = T.must(approval.organization)

    recipient_ids = organization.people_ids - [approver_id]

    recipient_ids.each_slice(BATCH_SIZE) do |people_ids|
      records = OauthAccessTokens.domain.by_users_and_application(people_ids, application.id, T.must(application.class.name))
      # Deduplicate records by user_id here
      accesses = records.group_by(&:user_id).map { |_, grouped| grouped.first }

      accesses.each do |oauth_access|
        next unless oauth_access
        recipient = oauth_access.user

        mail = OrganizationMailer.application_access_approved(
          recipient: recipient, organization: organization,
          application: application
        )

        mail.deliver_now
      end
    end
  end
end
