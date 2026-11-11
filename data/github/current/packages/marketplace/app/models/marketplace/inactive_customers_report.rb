# typed: true
# frozen_string_literal: true

class Marketplace::InactiveCustomersReport
  INACTIVE_CUSTOMER_COLUMNS_BY_HEADER = {
    "Login" => "users.login",
    "Type" => "users.type",
    "Email" => "user_emails.email",
    "Organization billing email" => "users.organization_billing_email",
    "Plan" => "marketplace_listing_plans.name",
  }
  SUBSCRIBABLE_INDEX = 4

  attr_reader :listing

  def initialize(listing:)
    @listing = listing
  end

  def as_csv
    CSV.generate do |csv|
      csv << headers

      inactive_customers.each do |inactive_customer|
        csv << inactive_customer
      end
    end
  end

  def filename
    "#{listing.slug}-inactive-customers-#{Date.current.strftime('%Y-%m')}.csv"
  end

  private

  def headers
    INACTIVE_CUSTOMER_COLUMNS_BY_HEADER.keys
  end

  def inactive_customers
    if break_joins?
      listing_plans_items = listing.
        subscription_items.
        active.
        not_installed.
        joins(:plan_subscription).
        pluck(:user_id, :subscribable_id).to_h
      listing_plans_ids = listing_plans_items.values
      listing_plans_names = listing.listing_plans.where(id: listing_plans_ids).pluck(:id, :name).to_h

      subscription_items = User.where(id: listing_plans_items.keys)
        .left_outer_joins(:primary_user_email)
        .pluck(Arel.sql(subscription_item_columns))
      subscription_items.each do |subscription_item|
        listing_plan_id = listing_plans_items[subscription_item[SUBSCRIBABLE_INDEX]]
        subscription_item[SUBSCRIBABLE_INDEX] = listing_plans_names[listing_plan_id]
      end
      subscription_items
    else
      subscription_items = listing.
        subscription_items.
        active.
        not_installed.
        left_outer_joins(plan_subscription: { user: :primary_user_email }).
        pluck(Arel.sql(subscription_item_columns))
      listing_plans_ids = subscription_items.map { |item| item[SUBSCRIBABLE_INDEX] }
      listing_plans_names = listing.listing_plans.where(id: listing_plans_ids).pluck(:id, :name).to_h

      subscription_items.each do |subscription_item|
        subscription_item[SUBSCRIBABLE_INDEX] = listing_plans_names[subscription_item[SUBSCRIBABLE_INDEX]]
      end
    end
  end

  def subscription_item_columns
    if break_joins?
      INACTIVE_CUSTOMER_COLUMNS_BY_HEADER.except("Plan").values.join(",") + ", users.id"
    else
      INACTIVE_CUSTOMER_COLUMNS_BY_HEADER.except("Plan").values.join(",") + ", subscribable_id"
    end
  end

  def break_joins?
    if Rails.env.test?  # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      true
    else
      FeatureFlag.vexi.enabled?(:break_join_inactive_customers_report, default: false)
    end
  end
end
