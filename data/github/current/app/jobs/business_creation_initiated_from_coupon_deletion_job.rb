# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class BusinessCreationInitiatedFromCouponDeletionJob < ApplicationJob
  queue_as :business_creation_initiated_from_coupon_deletion

  retry_on_dirty_exit
  discard_on ActiveJob::DeserializationError

  resolve_tenant_context do |business|
    business
  end

  def perform(business)
    return unless business&.creation_initiated_from_coupon?
    org = business.upgrade_initiated_from_organization

    if org.present?
      with_write { org.clear_upgrade_to_enterprise_in_progress! }
    end

    DestroyBusinessJob.perform_later(business.id)
  end
end
