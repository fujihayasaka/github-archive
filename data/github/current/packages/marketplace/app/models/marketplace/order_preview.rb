# typed: true
# frozen_string_literal: true

# Lifecycle of an order preview:
# - user views a preview the first time: create
# - user changes quantity/account/plan: update attrs & viewed_at
# - user purchases: destroy
# rubocop:todo GitHub/DatabaseModelsShouldHaveTests
class Marketplace::OrderPreview < ApplicationRecord::Domain::Integrations
  # rubocop:enable GitHub/DatabaseModelsShouldHaveTests
  self.table_name = "marketplace_order_previews"

  include GitHub::Relay::GlobalIdentification

  # rubocop:todo Rails/InverseOf
  belongs_to :listing, class_name: "Marketplace::Listing", foreign_key: "marketplace_listing_id"
  belongs_to :listing_plan, class_name: "Marketplace::ListingPlan", foreign_key: "marketplace_listing_plan_id"
  # rubocop:enable Rails/InverseOf
  belongs_to :user
  belongs_to :account, class_name: "User"

  scope :with_valid_listing_data, -> {
    joins(:listing, :listing_plan).merge(Marketplace::Listing.publicly_listed)
  }

  # targetable returns the OrderPreviews where there is not a related subscription.
  # an example use case is a user that has a subscription to a listing, then
  # previews that listing again in order to make an upgrade. We don't want to
  # target this person because they already have the listing installed.
  scope :targetable, -> {
    joins(:user).
    joins(:listing).
    joins("LEFT JOIN plan_subscriptions ON plan_subscriptions.user_id = users.id").
    joins("LEFT JOIN subscription_items ON subscription_items.plan_subscription_id = plan_subscriptions.id").
    joins(<<~SQL,
      LEFT JOIN marketplace_listing_plans
      ON (marketplace_listing_plans.id = subscription_items.subscribable_id AND
          subscription_items.subscribable_type = #{Billing::SubscriptionItem::MARKETPLACE_SUBSCRIBABLE_TYPE})
      AND marketplace_listing_plans.marketplace_listing_id = marketplace_listings.id
      SQL
    ).
    where(marketplace_listing_plans: { id: nil }).
    where(marketplace_listings: { state: ::Marketplace::Listing.publicly_listed_state_values }).
    where(marketplace_order_previews: { email_notification_sent_at: nil, retargeting_notice_triggered_at: nil }).
    annotate("cross-schema-domain-query-exempted")
  }

  scope :retargeting_notice_triggered, -> { where.not(retargeting_notice_triggered_at: nil) }

  def platform_type_name
    "MarketplaceOrderPreview"
  end

  def notification_sent?
    email_notification_sent_at.present?
  end
end
