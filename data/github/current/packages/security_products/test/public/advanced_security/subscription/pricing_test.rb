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
      GitHub.flipper[:ghas_self_serve_orgs].enable(@organization)

      price = @organization.advanced_security_price(seats: 10)

      assert_equal price.to_f, 490.0
    end

    test "returns the estimated price of a GHAS subscription given a number of seats when the user does not have a subscription" do
      GitHub.flipper[:ghas_self_serve_orgs].enable(@organization)

      price = @organization.advanced_security_price(seats: 10)

      refute @organization.subscribed_to_product?(@advanced_security_product_monthly)
      assert_equal price.to_f, 490.0
    end

    test "returns the monthly estimated price of a GHAS subscription given a number of seats when the user has a subscription" do
      GitHub.flipper[:ghas_self_serve_orgs].enable(@organization)

      result = @organization.subscribe_to_advanced_security(seats: 5, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      price = @organization.advanced_security_price(seats: 10, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      assert @organization.subscribed_to_product?(@advanced_security_product_monthly)
      assert_equal price.to_f, 490.0
    end

    test "returns the yearly estimated price of a GHAS subscription when the post-mvp feature flag is enabled" do
      GitHub.flipper[:ghas_self_serve_post_mvp].enable(@organization)
      GitHub.flipper[:ghas_self_serve_orgs].enable(@organization)

      result = @organization.subscribe_to_advanced_security(seats: 1, actor: @user,  billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Year)
      price = @organization.advanced_security_price(seats: 2, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Year)

      assert_equal price.to_f, 1176.0
    end

    test "returns error for a yearly price of a GHAS subscription when the post-mvp feature flag is disabled" do
      GitHub.flipper[:ghas_self_serve_post_mvp].disable
      GitHub.flipper[:ghas_self_serve_orgs].enable(@organization)

      assert_raises do
        price = @organization.advanced_security_price(seats: 2, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Year)
      end
    end
  end
end
