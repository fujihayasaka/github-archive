# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvancedSecuritySubscribableTest < GitHub::TestCase
  fixtures do
    @organization = create :credit_card_org
    @user = create :user
    @organization.add_admin(@user)

    @advanced_security_monthly_product_uuid = create(:billing_product_uuid, :advanced_security)
    @advanced_security_yearly_product_uuid = create(:billing_product_uuid, :advanced_security, :yearly)

    @advanced_security_monthly_product = AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT
    @advanced_security_yearly_product = AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_YEARLY_PRODUCT

  end

  context "#subscribe_to_product" do
    context "for GitHub Advanced Security" do
      test "succeeds when call to create successfully creates a monthly subscription item with an organization" do
        result = @organization.subscribe_to_product(@advanced_security_monthly_product, quantity: 5, actor: @user)
        assert result.ok?

        assert result.ok?
        assert @organization.subscribed_to_product?(@advanced_security_monthly_product)
      end

      test "succeeds when call to create successfully creates a yearly subscription item with an organization" do
        result = @organization.subscribe_to_product(@advanced_security_yearly_product, quantity: 5, actor: @user)
        assert result.ok?

        assert result.ok?
        assert @organization.subscribed_to_product?(@advanced_security_yearly_product)
      end

      test "fails when the actor should not be allowed to update the subscription" do
        @other_user = create :user, name: "other-user"
        result = @organization.subscribe_to_product(@advanced_security_monthly_product, quantity: 5, actor: @other_user)

        refute result.ok?
        refute @organization.subscribed_to_product?(@advanced_security_monthly_product)
      end
    end
  end

  context "#subscribed_to_product?" do
    context "for a GitHub Advanced Security" do
      test "before subscribing to the product, a organization is not subscribed" do
        refute @organization.subscribed_to_product?(@advanced_security_monthly_product)
      end

      test "after subscribing to the product, a organization is subscribed" do
        result = @organization.subscribe_to_product(@advanced_security_monthly_product, quantity: 5, actor: @user)

        assert @organization.subscribed_to_product?(@advanced_security_monthly_product)
      end
    end
  end
end
