# typed: strict
# frozen_string_literal: true

module Licensing
  class BundledLicenseAssignmentsAgreementUnlinkingJob < ApplicationJob
    queue_as :licensing
    retry_on_dirty_exit

    # only a single occurrence of this job should run at a given time based on the enterprise agreement number
    locked_by timeout: 1.minute, key: ->(job) {
      agreement_id = job.arguments[0]
      lock_key = "bundled_license_assignments_agreement_unlinking:#{agreement_id}"
    }

    before_enqueue do
      throw(:abort) unless GitHub.billing_enabled?
    end

    sig { params(agreement_id: String, revoke_blas: T.nilable(T::Boolean)).void }
    def perform(agreement_id, revoke_blas: false)
      raise "Agreement number is blank" if agreement_id.blank?

      enterprise_agreement = EnterpriseAgreement.find_by(agreement_id:)

      raise "Enterprise agreement still exists and is active " if enterprise_agreement&.active?

      assignments = Licensing::BundledLicenseAssignment.for_enterprise_agreement(agreement_id)

      with_write do
        update_attributes = { business_id: nil }
        update_attributes[:revoked] = true if revoke_blas
        assignments.update_all(update_attributes)
      end
    end
  end
end
