# typed: true
# frozen_string_literal: true

require "test_helper"

class SubscribableTest
  include Billing::Public::Product::Subscribable
end

class Billing::Public::Product::SubscribableTest < GitHub::TestCase
  fixtures do
    @organization = create :credit_card_org
    @user = create :user
    @organization.add_admin(@user)

    @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
    @advanced_security_monthly_product = AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT

    @subscribable = SubscribableTest.new.freeze
  end

  context "#subscribe_to_product" do
    test "creates a subscription item with the appropriate quantity on an organization subscription" do
      result = @organization.subscribe_to_product(@advanced_security_monthly_product, quantity: 5, actor: @user)

      assert result.ok?
      assert @organization.subscribed_to_product?(@advanced_security_monthly_product)
    end
  end

  context "#subscribed_to_product?" do
    context "for a GitHub Advanced Security" do
      test "before subscribing to the product, an organization is not subscribed" do
        refute @organization.subscribed_to_product?(@advanced_security_monthly_product)
      end

      test "after subscribing to the product, an organization is subscribed" do
        result = @organization.subscribe_to_product(@advanced_security_monthly_product, quantity: 5, actor: @user)

        assert @organization.subscribed_to_product?(@advanced_security_monthly_product)
      end
    end
  end
end
