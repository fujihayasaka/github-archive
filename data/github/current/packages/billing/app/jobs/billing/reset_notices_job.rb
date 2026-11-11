# typed: true
# frozen_string_literal: true

module Billing
  class ResetNoticesJob < BillingJob
    attr_reader :notice

    # Public: Resets the notices of all users with billing access for a given Business or Organization
    #
    # notice - The notice String key to be reset
    # billable_entity - The Business or Organization whose users with billing access will have the notice reset
    #
    # Returns nothing
    def perform(notice, billable_entity)
      @notice = notice

      if billable_entity.is_a?(Business)
        reset_business_notices(billable_entity)
      elsif billable_entity.organization?
        reset_organization_notices(billable_entity)
      end
    end

    def reset_business_notices(business)
      [business.owners, business.billing_managers].flatten.each do |user|
        with_write { user.reset_business_notice(notice, business_id: business.id) }
      end
    end

    def reset_organization_notices(organization)
      [organization.admins, organization.billing_managers].flatten.each do |user|
        with_write { user.reset_organization_notice(notice, organization) }
      end
    end
  end
end
