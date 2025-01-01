# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvancedSecurityInstrumenterTest < GitHub::TestCase
  fixtures do
    @business = create(:billing_plan_subscription, :business_owned).business
    @owner = @business.owners.first

    @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
    @advanced_security_product = AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT
  end

  context "subscription cancelled", skip_enterprise: true do
    test "resets ghas configuration" do
      # Arrange
      num_seats = 5
      @business.subscribe_to_advanced_security(seats: num_seats, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      subscription_item = @business.active_subscription_items.sole

      # Assume
      assert @business.reload.advanced_security_purchased_for_entity?
      assert_equal num_seats, @business.advanced_security_seats_for_entity

      # Act
      GitHub.instrument(
        "billing.subscription_item_cancelled",
          actor_id: @owner.id,
          user_id: @business.id,
          subscription_item_id: subscription_item.id,
          product_type: subscription_item.subscribable.product_type,
       )

      # Assert
      refute @business.reload.advanced_security_purchased_for_entity?
    end

    test "resets ghas configuration for organizations" do
      # Arrange
      enable_feature_flag(:ghas_self_serve_orgs)
      organization = create(:credit_card_organization, plan: GitHub::Plan.business_plus)
      owner = organization.owner
      num_seats = 5
      organization.subscribe_to_advanced_security(seats: num_seats, actor: owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      subscription_item = organization.active_subscription_items.sole

      # Assume
      assert organization.reload.advanced_security_purchased_for_entity?
      assert_equal num_seats, organization.advanced_security_seats_for_entity

      # Act
      GitHub.instrument(
        "billing.subscription_item_cancelled",
          actor_id: owner.id,
          user_id: organization.id,
          subscription_item_id: subscription_item.id,
          product_type: subscription_item.subscribable.product_type,
       )

      # Assert
      refute organization.reload.advanced_security_purchased_for_entity?
    end
  end
end
