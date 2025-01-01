# typed: true
# frozen_string_literal: true

require "test_helper"

class Businesses::EnterprisePaymentInfoReminderBannerComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @org_member = create(:user)
    @owner = create(:user)
    @org_admin = create(:user)
    @business = create(:business, :with_azure_subscription, owners: [@owner])
    @business.customer.update!(metered_plan: true)
    @org = create :organization, admins: [@org_admin], business: @business
    @org.add_member(@org_member)
    @billing_manager = create(:user)
    @business.billing.add_manager(@billing_manager, actor: @owner)
    @metered_business_with_cc = create(:business, :with_credit_card, owners: [@owner])
    @metered_business_with_cc.customer.update!(metered_plan: true)
  end

  test "does not render without business" do
    as @owner

    render_inline(Businesses::EnterprisePaymentInfoReminderBannerComponent.new(
      nil,
    ), allowed_queries: 0)

    refute_component_rendered
  end

  test "does not render for businesses on a metered trial" do
    as @owner

    @business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)

    render_inline(Businesses::EnterprisePaymentInfoReminderBannerComponent.new(
      @business,
    ), allowed_queries: 1)

    refute_component_rendered
  end

  test "does not render if metered ghe with linked azure subscription" do
    assert_predicate @business, :linked_azure_subscription?

    as @owner

    component = Businesses::EnterprisePaymentInfoReminderBannerComponent.new(@business)

    render_inline(component, allowed_queries: 1)

    refute_component_rendered
  end

  test "does not render if metered ghe with credit card and no azure subscription when FF enabled" do
    @metered_business_with_cc.enable_feature(:metered_ghe_cc_paypal_payments)
    assert_predicate @metered_business_with_cc, :has_credit_card?
    refute_predicate @metered_business_with_cc, :linked_azure_subscription?

    as @owner

    render_inline(Businesses::EnterprisePaymentInfoReminderBannerComponent.new(
      @metered_business_with_cc
    ), allowed_queries: 1)

    refute_component_rendered
  end

  test "renders if metered ghe with credit card and no azure subscription when FF disabled" do
    @metered_business_with_cc.disable_feature(:metered_ghe_cc_paypal_payments)
    assert_predicate @metered_business_with_cc, :has_credit_card?
    refute_predicate @metered_business_with_cc, :linked_azure_subscription?

    as @owner

    render_inline(Businesses::EnterprisePaymentInfoReminderBannerComponent.new(
      @metered_business_with_cc
    ), allowed_queries: 1)

    assert_test_selector "enterprise-payment-information-reminder-banner"
    assert_text "Missing payment information"
    assert_text "Add payment information"
  end

  context "when business is metered through Azure but missing Azure subscription info" do
    test "renders for enterprise owner" do
      as @owner

      @business.customer.update(azure_subscription_id: nil)

      render_inline(Businesses::EnterprisePaymentInfoReminderBannerComponent.new(
        @business
      ), allowed_queries: 1)

      assert_test_selector "enterprise-payment-information-reminder-banner"
      assert_text "Missing payment information"
      assert_text "Add payment information"
    end

    test "renders for billing manager" do
      as @billing_manager

      @business.customer.update(azure_subscription_id: nil)

      render_inline(Businesses::EnterprisePaymentInfoReminderBannerComponent.new(
        @business
      ), allowed_queries: 2)

      assert_test_selector "enterprise-payment-information-reminder-banner"
      assert_text "Missing payment information"
      assert_text "Add payment information"
    end

    test "does not render for org admin" do
      as @org_admin

      @business.customer.update(azure_subscription_id: nil)

      render_inline(Businesses::EnterprisePaymentInfoReminderBannerComponent.new(
        @business
      ), allowed_queries: 2)

      refute_component_rendered
    end

    test "does not render for org member" do
      as @org_member

      @business.customer.update(azure_subscription_id: nil)

      render_inline(Businesses::EnterprisePaymentInfoReminderBannerComponent.new(
        @business
      ), allowed_queries: 2)

      refute_component_rendered
    end
  end
end unless GitHub.enterprise?
