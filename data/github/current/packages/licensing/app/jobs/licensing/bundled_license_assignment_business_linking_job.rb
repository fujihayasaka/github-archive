# typed: true
# frozen_string_literal: true

module Licensing
  class BundledLicenseAssignmentBusinessLinkingJob < ApplicationJob
    queue_as :licensing
    retry_on_dirty_exit

    before_enqueue do
      throw(:abort) unless GitHub.billing_enabled?
    end

    def perform(enterprise_agreement)
      assignments = Licensing::BundledLicenseAssignment.nonrevoked.for_enterprise_agreement(enterprise_agreement.agreement_id)
      business = enterprise_agreement.business

      assignments.each do |assignment|
        with_write { assignment.update(business: business) }
      end
    end
  end
end
