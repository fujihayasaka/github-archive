# typed: true
# frozen_string_literal: true

module Billing
  class EnterpriseCloudTrialCheckJob < BillingJob
    queue_as :billing

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    def perform(organization_id)
      organization = Organization.find(organization_id)
      organization_in_trial = Billing::EnterpriseCloudTrial.new(organization).ever_been_in_trial?
      business_in_trial = organization.business&.trial?

      if organization_in_trial || business_in_trial
        organization.members.find_each do |member|
          with_write { GlobalNoticeNext.new(viewer: member).set_notice(:enterprise_cloud_trial) }
        end
      end
    end
  end
end
