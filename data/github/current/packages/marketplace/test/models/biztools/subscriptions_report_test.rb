# typed: true
# frozen_string_literal: true

require "test_helper"

class SubscriptionsReportTest < GitHub::TestCase
  fixtures do
    @listing = create(:marketplace_listing)
    @report = Biztools::SubscriptionsReport.new(listing: @listing).freeze
  end

  context "#filename" do
    test "generates a filename" do
      assert_equal "#{@listing.name}-subscription-user-details.csv", @report.filename
    end
  end

  context "#as_csv" do
    test "returns the right headers" do
      assert_equal Biztools::SubscriptionsReport::CSV_HEADERS, @report.as_csv.split("\n").first.split(",")
    end

    test "returns the right values" do
      listing = create(:marketplace_listing)
      report = Biztools::SubscriptionsReport.new(listing: listing).freeze
      plan_subscription = create(:billing_plan_subscription, :zuora)
      plan = create(:marketplace_listing_plan, :published, :per_unit, listing: listing)

      item = create(
        :billing_subscription_item,
        plan_subscription: plan_subscription,
        subscribable: plan,
        quantity: 10,
      )

      assert_equal listing.subscription_items.count, report.as_csv.split("\n").count - 1
      assert_equal report.as_csv.split("\n"), ["User Type,Name,Email,Plan Name,Price Interval,Price", "User,#{plan_subscription.user.display_login},#{plan_subscription.user.email},#{plan.name},#{item.billing_interval},#{item.price.format}"]
    end

    test "skips over subscription without a user" do
      listing = create(:marketplace_listing)
      report = Biztools::SubscriptionsReport.new(listing: listing).freeze
      plan_subscription = create(:billing_plan_subscription, :zuora)
      plan = create(:marketplace_listing_plan, :published, :per_unit, listing: listing)

      item = create(
        :billing_subscription_item,
        plan_subscription: plan_subscription,
        subscribable: plan,
        quantity: 10,
      )

      # Simulate destroying a user without triggering any callbacks
      item.user.delete

      assert_equal listing.subscription_items.count - 1, report.as_csv.split("\n").count - 1
      assert_equal report.as_csv.split("\n"), ["User Type,Name,Email,Plan Name,Price Interval,Price"]
    end
  end
end
