# typed: true
# frozen_string_literal: true

module Licensing
  class LicenseSnapshotForExpiredRepositoryInvitationsJob < ApplicationJob
    queue_as :licensing
    retry_on_dirty_exit
    schedule interval: 1.day, condition: -> { GitHub.billing_enabled? }
    exempt_from_tenant_context_requirement

    before_enqueue do
      throw(:abort) unless GitHub.billing_enabled?
    end

    def perform
      owner_ids = Repository.where(id: RepositoryInvitation.recently_expired.pluck(:repository_id)).pluck(:owner_id)
      business_ids = Business::OrganizationMembership.where(organization_id: owner_ids).select(:business_id).distinct.pluck(:business_id)
      Business.where(id: business_ids).each do |business|
        Licensing::SnapshotLicensesJob.perform_later(business)
      end
    end
  end
end
