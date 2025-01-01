# typed: true
# frozen_string_literal: true

module Billing::Notifications
  class NotificationPermission

    attr_reader :owner

    def initialize(owner, product: nil)
      @owner = owner
      @product = product
    end

    def receive_notification_for_free_usage?
      !free_usage_notification_disabled_in_current_cycle? ||
        !overages_enabled_for_product?
    end

    def receive_notification_for_paid_usage?
      overages_enabled_for_product?
    end

    def free_usage_notification_disabled_in_current_cycle?
      Billing::Kv.store.exists(free_usage_notification_disabled_key).value { true }
    end

    def disable_free_usage_notification_in_current_cycle
      Billing::Kv.store.set(free_usage_notification_disabled_key, Time.now.to_s, expires: @owner.next_metered_billing_cycle_starts_at)
    end

    private

    def overages_enabled_for_product?
      @owner.metered_billing_overage_allowed?(product: @product)
    end

    def free_usage_notification_disabled_key
      [
        "disable-entitlement-notification",
        @owner.class.to_s.downcase,
        @owner.id,
        @owner.current_metered_billing_cycle_starts_at.to_date
      ].join("-")
    end
  end
end
