# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::Notifications
  class BudgetThresholdBannerTest < GitHub::TestCase
    include Billing::Platform::Api::Utils

    fixtures do
      @business = create(:business)
      @current_user = create(:user)
    end

    context "#visible?" do
      test "returns true if the notification hasn't been dismissed" do
        budget = create(:budget, targetId: @business.customer.id, targetType: CUSTOMER_TARGET, currentAmount: 80.0, threshold_percentage: 75, threshold_alertable: true)
        notification = BudgetNotification.new(budget: budget)
        banner = BudgetThresholdBanner.new(budget_notification: notification, actor: @current_user)

        assert banner.visible?
      end

      test "returns false if the notification has been dismissed" do
        budget = create(:budget, targetId: @business.customer.id, targetType: CUSTOMER_TARGET, currentAmount: 80.0, targetAmount: 100.0, uuid: "1234", threshold_percentage: 75, threshold_alertable: true)

        # dismiss banner
        key = "billing_platform-budget_1234-100.0-threshold_75"
        product_tag = "billing_platform_SkuPricing"
        dismiss = Billing::Notifications::Dismissal.new(account: @business, actor_id: @current_user.id)
        dismiss.create(key, product_tag: product_tag)

        notification = BudgetNotification.new(budget: budget)
        banner = BudgetThresholdBanner.new(budget_notification: notification, actor: @current_user)

        refute banner.visible?
      end
    end

    context "#dismissible?" do
      # test "returns true if budget is NOT fully funded" do
      #   budget = create(:budget, targetId: @business.customer.id, targetType: CUSTOMER_TARGET, currentAmount: 80.0, targetAmount: 100.0, threshold_percentage: 0.75, threshold_alertable: true, isFullyFunded: false)
      #   notification = BudgetNotification.new(budget: budget)
      #   banner = BudgetThresholdBanner.new(budget_notification: notification, actor: @current_user)

      #   assert banner.dismissible?
      # end

      test "returns false if the budget is fully funded" do
        budget = create(:budget, targetId: @business.customer.id, targetType: CUSTOMER_TARGET, currentAmount: 100.0, targetAmount: 100.0, threshold_percentage: 1, threshold_alertable: true, isFullyFunded: true)
        notification = BudgetNotification.new(budget: budget)
        banner = BudgetThresholdBanner.new(budget_notification: notification, actor: @current_user)

        refute banner.dismissible?
      end
    end

    context "#dismissal_path" do
      test "returns the path for posting the dismiss request" do
        budget = create(:budget, targetId: @business.customer.id, targetType: CUSTOMER_TARGET, currentAmount: 100.0, targetAmount: 100.0, uuid: "12345", threshold_percentage: 100, threshold_alertable: true)
        notification = BudgetNotification.new(budget: budget)
        banner = BudgetThresholdBanner.new(budget_notification: notification, actor: @current_user)

        generated_path = banner.dismissal_path

        assert_includes generated_path, "/billing/notifications/dismissals?"
        assert_includes generated_path, "account_type=Business"
        assert_includes generated_path, "account_id=#{@business.id}"
        assert_includes generated_path, "notice_key=billing_platform-budget_12345-100.0-threshold_100"
        assert_includes generated_path, "product_tags%5B%5D=billing_platform_SkuPricing"
      end
    end
  end
end
