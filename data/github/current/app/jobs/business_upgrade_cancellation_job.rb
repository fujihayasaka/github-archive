# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class BusinessUpgradeCancellationJob < ApplicationJob
  queue_as :business_upgrade_cancellation

  retry_on_dirty_exit
  discard_on ActiveJob::DeserializationError

  resolve_tenant_context do |business|
    business
  end

  def perform(business, email_owners = true)
    # Business must be initiated either from a Free/Team paid org upgrade, or from a coupon
    return unless business.organization_upgrade_initiated? || business.creation_initiated_from_coupon?

    org = business.upgrade_initiated_from_organization

    if org.nil?
      GitHub.logger.warn(
        "EA upgrade cancelled without existing org",
        "gh.business.id" => business.id,
        "gh.business.name" => business.slug
      )
    end

    if email_owners && org.present?
      BillingNotificationsMailer.organization_upgrade_failure(org).deliver_later
    end

    if org.present?
      with_write { org.clear_upgrade_to_enterprise_in_progress! }
    end

    DestroyBusinessJob.perform_later(business.id)
  end
end
