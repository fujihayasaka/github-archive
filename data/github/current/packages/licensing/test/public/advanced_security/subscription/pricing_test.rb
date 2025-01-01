# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvancedSecurity::Public::PricingTest < GitHub::TestCase
  fixtures do
    @organization = create :credit_card_org
    @user = create :user
    @organization.add_admin(@user)

    create(:billing_product_uuid, :advanced_security)
    create(:billing_product_uuid, :advanced_security, :yearly)
    @advanced_security_product_monthly = AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT
  end

  context "#advanced_security_price" do
    test "returns the monthly estimated price of a GHAS subscription by default" do
      enable_feature_flag(:ghas_self_serve_orgs, @organization)

      price = @organization.advanced_security_price(seats: 10)

      assert_equal price.to_f, 490.0
    end

    test "returns the estimated price of a GHAS subscription given a number of seats when the user does not have a subscription" do
      enable_feature_flag(:ghas_self_serve_orgs, @organization)

      price = @organization.advanced_security_price(seats: 10)

      refute @organization.subscribed_to_product?(@advanced_security_product_monthly)
      assert_equal price.to_f, 490.0
    end

    test "returns the monthly estimated price of a GHAS subscription given a number of seats when the user has a subscription" do
      enable_feature_flag(:ghas_self_serve_orgs, @organization)

      result = @organization.subscribe_to_advanced_security(seats: 5, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      price = @organization.advanced_security_price(seats: 10, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      assert @organization.subscribed_to_product?(@advanced_security_product_monthly)
      assert_equal price.to_f, 490.0
    end

    test "returns the yearly estimated price of a GHAS subscription when the post-mvp feature flag is enabled" do
      enable_feature_flag(:ghas_self_serve_post_mvp, @organization)
      enable_feature_flag(:ghas_self_serve_orgs, @organization)

      result = @organization.subscribe_to_advanced_security(seats: 1, actor: @user,  billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Year)
      price = @organization.advanced_security_price(seats: 2, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Year)

      assert_equal price.to_f, 1176.0
    end

    test "returns error for a yearly price of a GHAS subscription when the post-mvp feature flag is disabled" do
      disable_feature_flag(:ghas_self_serve_post_mvp)
      enable_feature_flag(:ghas_self_serve_orgs, @organization)

      assert_raises do
        price = @organization.advanced_security_price(seats: 2, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Year)
      end
    end
  end

  context "#advanced_security_price_for_sku", skip_enterprise: true do
    test "returns correct price for secret protection licenses" do
      Billing::Platform::Api::Client.any_instance
        .stubs(:get_pricing)
        .with(sku: "ghas_secret_protection_licenses")
        .returns({
          pricing: {
            price: 19.0,
          }
        })
      price = @organization.advanced_security_price_for_sku(
        sku: "ghas_secret_protection_licenses",
        seats: 10
      )
      assert_equal price.to_f, 190.0
    end

    test "returns correct price for code security licenses" do
      Billing::Platform::Api::Client.any_instance
        .stubs(:get_pricing)
        .with(sku: "ghas_code_security_licenses")
        .returns({
          pricing: {
            price: 30.0,
          }
        })
      price = @organization.advanced_security_price_for_sku(
        sku: "ghas_code_security_licenses",
        seats: 10
      )
      assert_equal price.to_f, 300.0
    end

    test "raises InvalidSkuError for invalid SKU" do
      assert_raises(AdvancedSecurity::Public::Pricing::InvalidSkuError) do
        @organization.advanced_security_price_for_sku(
          sku: "invalid_sku",
          seats: 10
        )
      end
    end

    test "falls back to hardcoded price when API returns error" do
      Billing::Platform::Api::Client.any_instance
        .stubs(:get_pricing)
        .with(sku: "ghas_secret_protection_licenses")
        .returns(::Billing::Platform::Api::Error.new("API Error"))
      price = @organization.advanced_security_price_for_sku(
        sku: "ghas_secret_protection_licenses",
        seats: 10
      )
      assert_equal price.to_f, 190.0

      needle = Failbot.reports.first
      assert_equal needle["exception_detail"].first["type"], "Billing::Platform::Api::Error"
      assert_equal needle["sensitive_context"]["sku"], "ghas_secret_protection_licenses"
    end

    test "falls back to hardcoded price when API returns blank pricing" do
      Billing::Platform::Api::Client.any_instance
        .stubs(:get_pricing)
        .with(sku: "ghas_secret_protection_licenses")
        .returns({ pricing: nil })

      price = @organization.advanced_security_price_for_sku(
        sku: "ghas_secret_protection_licenses",
        seats: 10
      )
      assert_equal price.to_f, 190.0
    end
  end
end
