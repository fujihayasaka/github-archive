# typed: true
# frozen_string_literal: true

require "test_helper"

class MarketplaceInactiveCustomersReportTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @listing = create(:marketplace_listing)
    @listing_plan = create(:marketplace_listing_plan, :published, listing: @listing)
    @report = Marketplace::InactiveCustomersReport.new(listing: @listing)
  end

  context "#as_csv" do
    test "returns a string-rendered csv" do
      active_customer_item = create(:billing_subscription_item, :installed, subscribable: @listing_plan)
      inactive_customer_item = create(:billing_subscription_item, :not_installed, subscribable: @listing_plan)

      actual_csv_string = @report.as_csv
      assert_includes actual_csv_string, inactive_customer_item.account.login
      refute_includes actual_csv_string, active_customer_item.account.login

      actual_rows = actual_csv_string.split("\n")

      expected_headers = Marketplace::InactiveCustomersReport::INACTIVE_CUSTOMER_COLUMNS_BY_HEADER.keys
      assert_match expected_headers.join(","), actual_rows.first

      expected_inactive_customer_data = [
        inactive_customer_item.account.login,
        inactive_customer_item.account.type,
        inactive_customer_item.account.email,
        inactive_customer_item.account.organization_billing_email,
        inactive_customer_item.subscribable_name,
      ]
      assert_match expected_inactive_customer_data.join(","), actual_rows.second
    end
  end
end
