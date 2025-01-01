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

  def subscription_item_columns
    INACTIVE_CUSTOMER_COLUMNS_BY_HEADER.except("Plan").values.join(",") + ", subscribable_id"
  end
end
