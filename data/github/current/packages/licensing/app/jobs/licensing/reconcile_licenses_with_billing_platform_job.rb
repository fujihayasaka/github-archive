# typed: true
# frozen_string_literal: true

class Licensing::ReconcileLicensesWithBillingPlatformJob < ApplicationJob

  queue_as :licensing

  retry_on_recoverable_exceptions
  retry_on_dirty_exit

  SKU = T.let("ghec_seats".freeze, String)

  sig { params(business: Business).void }
  def perform(business)
    client = Billing::Platform::Api::Client.new
    customer_id = business.customer_id.to_s
    ghec_subscriptions = client.get_subscribed_items(usage_entity_id: customer_id, sku: SKU)

    # We don't want to continue if we can't get the subscriptions.
    raise ghec_subscriptions if ghec_subscriptions.is_a?(Billing::Platform::Api::Error)

    active_subscribers_in_billing_platform = ghec_subscriptions[:subscribedItems].collect do |subscriber|
      if subscriber[:lastBilledForAt] == 0
        subscriber[:subscriptionId]
      end
    end.compact

    active_subscribers = business.user_accounts.where(ghec_license: true).pluck(:user_id)

    # Add licenses for active subscribers
    (active_subscribers - active_subscribers_in_billing_platform).each do |user_id|
      business.user_accounts.find_by(user_id: user_id)&.emit_added_license_billing_message
    end

    # Remove licenses for inactive subscribers
    (active_subscribers_in_billing_platform - active_subscribers).each do |user_id|
      BusinessUserAccount.new(user_id: user_id, business: business).emit_removed_license_billing_message
    end
  end
end
