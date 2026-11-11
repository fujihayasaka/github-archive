# typed: strict
# frozen_string_literal: true

module Licensing
  class ScheduledFullLicenseSyncJob < ApplicationJob
    queue_as :licensing
    schedule interval: 1.hour, condition: -> { GitHub.billing_enabled? }
    retry_on_dirty_exit
    exempt_from_tenant_context_requirement

    # Spread daily license syncs across hours 0-9 UTC by matching the last
    # digit of each business ID to the current hour. Businesses whose ID ends
    # in 0 are processed at 00:00, those ending in 1 at 01:00, etc.
    # Hours 10-23 are intentionally skipped to avoid peak traffic windows.
    SYNC_HOURS = T.let((0..9).to_a.freeze, T::Array[Integer])

    sig { void }
    def perform
      current_hour = Time.now.utc.hour
      return unless SYNC_HOURS.include?(current_hour)

      businesses = businesses_with_active_vss_bundle(last_digit: current_hour)
      synced_count = 0

      businesses.find_each do |business|
        customer_id = business.customer_id
        next unless customer_id

        Licensing::SyncCustomerLicensesInLicensifyJob.perform_later(customer_id)
        synced_count += 1
      end

      GitHub.dogstats.gauge("licensing.scheduled_full_license_sync.count", synced_count, tags: [
        "hour:#{current_hour}",
      ])
    end

    private

    # EnterpriseAgreement lives in the billing database while Business lives
    # in the users database, so we cannot do a cross-database join. Instead,
    # collect the qualifying business IDs from the billing side first, then
    # look them up on the users side.
    sig { params(last_digit: Integer).returns(ActiveRecord::Relation) }
    def businesses_with_active_vss_bundle(last_digit:)
      vss_business_ids = Licensing::EnterpriseAgreement
        .active
        .visual_studio_bundle
        .where("business_id % 10 = ?", last_digit)
        .distinct
        .pluck(:business_id)

      Business
        .where(id: vss_business_ids)
    end
  end
end
