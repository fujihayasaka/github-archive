# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PackageRegistryUsageTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers

  context "when using .usage_quote" do
    context "#has_error?" do
      test "returns false on successful api call" do
        stub_shared_products_usage_response(proposed_gigabytes: 4.9.gigabytes)
        user = create(:user)
        registry_usage = Billing::PackageRegistryUsage.usage_quote(user)

        refute registry_usage.has_error?
      end

      test "return true on failed api call" do
        mock_calculate_usage_quotes_response_error
        user = create(:user)
        registry_usage = Billing::PackageRegistryUsage.usage_quote(user)

        assert registry_usage.has_error?
      end
    end

    context "#total_gigabytes_used" do
      test "returns the total gigabytes used" do
        stub_shared_products_usage_response(proposed_gigabytes: 4.9.gigabytes)
        user = create(:credit_card_user, plan: GitHub::Plan.pro, plan_duration: "month", billed_on: GitHub::Billing.today + 10.days)
        registry_usage = Billing::PackageRegistryUsage.usage_quote(user)

        assert_equal 5, registry_usage.total_gigabytes_used
      end

      test "returns nil on api error" do
        mock_calculate_usage_quotes_response_error
        user = create(:credit_card_user, plan: GitHub::Plan.pro, plan_duration: "month", billed_on: GitHub::Billing.today + 10.days)
        registry_usage = Billing::PackageRegistryUsage.usage_quote(user)

        assert_nil registry_usage.total_gigabytes_used
      end
    end

    context "#billable_gigabytes" do
      test "returns paid gigabytes minus included units for the users plan" do
        stub_shared_products_usage_response(proposed_gigabytes: 4.5.gigabytes)
        user = create(:user, plan: GitHub::Plan.free)
        registry_usage = Billing::PackageRegistryUsage.usage_quote(user)

        # 4.5GB usage rounded up to 5 GB billable Gigabytes
        assert_equal 5 - registry_usage.plan_included_bandwidth, registry_usage.billable_gigabytes
      end

      test "returns paid gigabytes plus addional gigs minus included units for the users plan" do
        stub_shared_products_usage_response(proposed_gigabytes: 5.1.gigabytes)
        user = create(:user, plan: GitHub::Plan.free)
        registry_usage = Billing::PackageRegistryUsage.usage_quote(user, additional_gigabytes: 0.6)

        # 4.5GB + 0.6GB = 5.1GB which rounds to 6 GB Billable Gigabytes
        assert_equal 6 - registry_usage.plan_included_bandwidth, registry_usage.billable_gigabytes
      end

      test "returns nil on api error" do
        mock_calculate_usage_quotes_response_error
        user = create(:credit_card_user, plan: GitHub::Plan.pro, plan_duration: "month", billed_on: GitHub::Billing.today + 10.days)
        registry_usage = Billing::PackageRegistryUsage.usage_quote(user)

        assert_nil registry_usage.billable_gigabytes
      end
    end

    context "#paid_usage_percentage" do
      test "returns 0 when there's no paid usage" do
        stub_shared_products_usage_response(proposed_gigabytes: 0)
        user = create(:user)
        usage = Billing::PackageRegistryUsage.usage_quote(user)

        assert_equal 0, usage.paid_usage_percentage
      end

      test "returns the percentage of paid usage to included" do
        stub_shared_products_usage_response(proposed_gigabytes: 4.5.gigabytes)
        user = create(:user, plan: GitHub::Plan.free)
        registry_usage = Billing::PackageRegistryUsage.usage_quote(user)

        assert_equal 400, registry_usage.paid_usage_percentage
      end

      test "returns nil on api error" do
        mock_calculate_usage_quotes_response_error
        user = create(:user, plan: GitHub::Plan.free)
        registry_usage = Billing::PackageRegistryUsage.usage_quote(user)

        assert_nil registry_usage.paid_usage_percentage
      end
    end

    context "#included_usage_percentage" do
      test "returns 100 when user has used all of their included usage" do
        stub_shared_products_usage_response(proposed_gigabytes: 1.gigabytes)
        user = create(:user, plan: GitHub::Plan.free) # 1gb included
        usage = Billing::PackageRegistryUsage.usage_quote(user)

        # 1gb used / 1 included
        assert_equal 100, usage.included_usage_percentage
      end

      test "returns percentage when user has used a portion of their included usage" do
        stub_shared_products_usage_response(proposed_gigabytes: 1.gigabytes)
        user = create(:user, plan: GitHub::Plan.pro) # 5gb included
        usage = Billing::PackageRegistryUsage.usage_quote(user)

        # 1gb used / 5 included
        assert_equal (1.to_f / user.plan.package_registry_included_bandwidth) * 100, usage.included_usage_percentage
      end

      test "returns nil on api error" do
        mock_calculate_usage_quotes_response_error
        user = create(:user, plan: GitHub::Plan.free)
        registry_usage = Billing::PackageRegistryUsage.usage_quote(user)

        assert_nil registry_usage.included_usage_percentage
      end
    end
  end

  context "when using '.product_usage'" do
    context "#has_error?" do
      test "returns false on successful api call" do
        mock_list_product_usage_response(product: "packages", sku_name: "default", unit_of_measure: "Megabytes", quantity: 4.9.gigabytes)
        user = create(:user)
        registry_usage = Billing::PackageRegistryUsage.product_usage(user)

        refute registry_usage.has_error?
      end

      test "return true on failed api call" do
        mock_list_product_usage_response_error
        user = create(:user)
        registry_usage = Billing::PackageRegistryUsage.product_usage(user)

        assert registry_usage.has_error?
      end
    end

    context "#total_gigabytes_used" do
      test "returns the total gigabytes used" do
        mock_list_product_usage_response(product: "packages", sku_name: "default", unit_of_measure: "Megabytes", quantity: 4.9.gigabytes)
        user = create(:credit_card_user, plan: GitHub::Plan.pro, plan_duration: "month", billed_on: GitHub::Billing.today + 10.days)
        registry_usage = Billing::PackageRegistryUsage.product_usage(user)

        assert_equal 5, registry_usage.total_gigabytes_used
      end

      test "returns nil on api error" do
        mock_list_product_usage_response_error
        user = create(:credit_card_user, plan: GitHub::Plan.pro, plan_duration: "month", billed_on: GitHub::Billing.today + 10.days)
        registry_usage = Billing::PackageRegistryUsage.product_usage(user)

        assert_nil registry_usage.total_gigabytes_used
      end
    end

    context "#billable_gigabytes" do
      test "returns paid gigabytes minus included units for the users plan" do
        mock_list_product_usage_response(product: "packages", sku_name: "default", unit_of_measure: "Megabytes", quantity: 4.5.gigabytes)
        user = create(:user, plan: GitHub::Plan.free)
        registry_usage = Billing::PackageRegistryUsage.product_usage(user)

        # 4.5GB usage rounded up to 5 GB billable Gigabytes
        assert_equal 5 - registry_usage.plan_included_bandwidth, registry_usage.billable_gigabytes
      end

      test "returns nil on api error" do
        mock_list_product_usage_response_error
        user = create(:credit_card_user, plan: GitHub::Plan.pro, plan_duration: "month", billed_on: GitHub::Billing.today + 10.days)
        registry_usage = Billing::PackageRegistryUsage.product_usage(user)

        assert_nil registry_usage.billable_gigabytes
      end
    end
  end
end if GitHub.billing_enabled?
