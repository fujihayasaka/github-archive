# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::Notifications
  class BudgetNotificationTest < GitHub::TestCase
    include Billing::Platform::Api::Utils

    fixtures do
      @business = create(:business)
      @org = create(:organization, :zuora)
    end

    context "#has_result?" do
      test "is false if threshold is not alertable" do
        budget = create(:budget, targetId: @business.customer.id, targetType: CUSTOMER_TARGET, threshold_alertable: false)
        notification = BudgetNotification.new(budget: budget)

        refute notification.has_result?
      end

      test "returns true if threshold is alertable" do
        budget = create(:budget, targetId: @business.customer.id, targetType: CUSTOMER_TARGET, currentAmount: 75, threshold_percentage: 0.75, threshold_alertable: true)
        notification = BudgetNotification.new(budget: budget)

        assert notification.has_result?
      end

      test "returns false if current amount is 0" do
        budget = create(:budget, targetId: @business.customer.id, targetType: CUSTOMER_TARGET, currentAmount: 0, threshold_percentage: 0.75, threshold_alertable: true)
        notification = BudgetNotification.new(budget: budget)

        refute notification.has_result?
      end

      test "returns true if the current amount is 75 but the budget target is changed to $0" do
        budget = create(:budget, targetId: @business.customer.id, targetType: CUSTOMER_TARGET, currentAmount: 75, targetAmount: 0, threshold_percentage: 0.75, threshold_alertable: true)
        notification = BudgetNotification.new(budget: budget)

        assert notification.has_result?
      end
    end

    context "#serialize" do
      test "returns nil when billable owner has legacy plan" do
        @org.plan = GitHub::Plan.gold
        budget = create(:budget, targetId: @org.id, targetType: :Org)
        notification = BudgetNotification.new(budget: budget)

        assert_nil notification.serialize
      end

      test "returns nil when budget is not alertable" do
        budget = create(:budget, targetId: @business.customer.id, targetType: CUSTOMER_TARGET, threshold_alertable: false)
        notification = BudgetNotification.new(budget: budget)

        assert_nil notification.serialize
      end

      test "returns BudgetNotificationSerializer if budget is alertable" do
        budget = create(:budget, targetId: @business.customer.id, targetType: CUSTOMER_TARGET, currentAmount: 75.0, threshold_percentage: 0.75, threshold_alertable: true)
        notification = BudgetNotification.new(budget: budget).serialize

        assert_equal 75.0, budget.current_amount
        assert notification.present?
      end

      test "returns the correct notification text for the budget scope and product" do
        budget = create(:budget, targetId: @business.customer.id, targetType: CUSTOMER_TARGET, pricingTargetType: "ProductPricing", pricingTargetId: "git_lfs", currentAmount: 75.0, threshold_percentage: 75.0, threshold_alertable: true)
        notification = BudgetNotification.new(budget: budget).serialize

        assert_includes notification&.text,  "Git LFS"
        assert includes notification&.text,  "Enterprise"
      end

      test "returns the correct notification text for a cost center budget" do
        budget = create(:budget, customerId: @business.customer.id, targetId: "cost-center-uuid", targetType: COSTCENTER_TARGET, pricingTargetType: "ProductPricing", pricingTargetId: "git_lfs", currentAmount: 75.0, threshold_percentage: 75.0, threshold_alertable: true)
        notification = BudgetNotification.new(budget: budget).serialize

        assert_includes notification&.text,  "Git LFS"
        assert includes notification&.text,  "cost center"
      end
    end

    context "#active_budget" do
      test "returns the passed budget" do
        budget = create(:budget, targetId: @business.customer.id, targetType: CUSTOMER_TARGET)
        notification = BudgetNotification.new(budget: budget)

        assert_equal budget, notification.active_budget
      end
    end

    test "creates notification for vnext org and individual top-level budgets" do
      if GitHub.enterprise?
        skip "Test not in an enterprise context"
      end

      enable_feature_flag(:onboard_new_individual_free_plan_to_billing_platform)
      user = create(:user, plan: "free", login: "free-plan-user")
      user.onboard_to_billing
      budget = create(:budget, targetId: user.customer.id, targetType: CUSTOMER_TARGET, threshold_alertable: true, currentAmount: 75.0, threshold_percentage: 75.0)
      notification = BudgetNotification.new(budget: budget).serialize
      refute_nil notification
    end
  end
end
