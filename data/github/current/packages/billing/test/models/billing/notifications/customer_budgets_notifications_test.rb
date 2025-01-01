# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::Notifications
  class CustomerBudgetsNotificationsTest < GitHub::TestCase
    include ::Billing::Platform::Api::TestHelpers
    include Billing::Platform::Api::Utils

    fixtures do
      @current_user = create(:user)
      @org_admin = create(:user)
      @billing_manager = create(:user)
      @owner = create(:user)
      @business = create(:business, owners: [@owner])
      @business.billing.add_manager(@billing_manager, actor: @business.owners.first)
      @business_org = create(:enterprise_linked_organization , business: @business, admin: @org_admin)
    end

    context "#budget_notifications" do
      test "returns empty array if api call raises exception" do
        mock_get_all_budgets_response_error
        notification = CustomerBudgetsNotifications.new(owner: @business)

        assert_empty notification.budget_notifications
      end

      test "returns array of BudgetNotification when there are valid budgets with result" do
        mock_get_all_budgets_response(customer_id: @business.customer.id, target_type: CUSTOMER_TARGET, target_id: @business.customer.id, current_amount: 75.0, threshold_percentage: 0.75, threshold_alertable: true)

        customer_notification = CustomerBudgetsNotifications.new(owner: @business)
        notifications = customer_notification.budget_notifications

        assert notifications.present?
        assert_equal 1, notifications.count
      end

      test "returns empty array if the available budget has alert turned off" do
        mock_get_all_budgets_response(customer_id: @business.customer.id, target_type: CUSTOMER_TARGET, target_id: @business.customer.id, current_amount: 75.0, will_alert: false, threshold_percentage: 0.75, threshold_alertable: true)

        customer_notification = CustomerBudgetsNotifications.new(owner: @business)
        notifications = customer_notification.budget_notifications

        assert_empty notifications
      end

      test "returns empty array if the available budget hasn't reached threshold" do
        mock_get_all_budgets_response(customer_id: @business.customer.id, target_type: CUSTOMER_TARGET, target_id: @business.customer.id, current_amount: 70.0, threshold_percentage: 0.0, threshold_alertable: false)

        customer_notification = CustomerBudgetsNotifications.new(owner: @business)
        notifications = customer_notification.budget_notifications

        assert_empty notifications
      end

      test "returns empty array if the available budget doesn't have owner" do
        mock_get_all_budgets_response(customer_id: @business.customer.id, target_type: CUSTOMER_TARGET, target_id: "invalid-id", current_amount: 80.0, threshold_percentage: 0.75, threshold_alertable: true)

        customer_notification = CustomerBudgetsNotifications.new(owner: @business)
        notifications = customer_notification.budget_notifications

        assert_empty notifications
      end

      test "excludes repo budget notifications if billing manager" do
        business_org_two = create :enterprise_linked_organization, admins: [@business_org_admin], business: @business, login: "monalisatwo"
        repo = create(:repository, owner: business_org_two)
        mock_get_all_budgets_response(customer_id: @business.customer.id, target_type: "Repo", target_id: repo.id.to_s, current_amount: 75.0, threshold_percentage: 0.75, threshold_alertable: true)
        customer_notification = CustomerBudgetsNotifications.new(owner: @business, actor: @billing_manager)
        notifications = customer_notification.budget_notifications

        assert_empty notifications
      end

      test "excludes repo budget notifications if owner" do
        business_org_two = create :enterprise_linked_organization, admins: [@business_org_admin], business: @business, login: "monalisatwo"
        repo = create(:repository, owner: business_org_two)
        mock_get_all_budgets_response(customer_id: @business.customer.id, target_type: "Repo", target_id: repo.id.to_s, current_amount: 75.0, threshold_percentage: 0.75, threshold_alertable: true)
        customer_notification = CustomerBudgetsNotifications.new(owner: @business, actor: @owner)
        notifications = customer_notification.budget_notifications

        assert_empty notifications
      end

      test "excludes non-repo budget notifications if org admin" do
        repo = create(:repository, owner: @business_org)
        mock_get_all_budgets_response(customer_id: @business.customer.id, target_type: "Repo", target_id: repo.id.to_s, current_amount: 75.0, threshold_percentage: 0.75, threshold_alertable: true)
        customer_notification = CustomerBudgetsNotifications.new(owner: @business, actor: @org_admin)
        notifications = customer_notification.budget_notifications

        refute_empty notifications
      end

      test "keeps budgets if both owner and org admin" do
        @business_org.add_admin(@owner)
        repo = create(:repository, owner: @business_org)
        mock_get_all_budgets_response(customer_id: @business.customer.id, target_type: "Repo", target_id: repo.id.to_s, current_amount: 75.0, threshold_percentage: 0.75, threshold_alertable: true)
        customer_notification = CustomerBudgetsNotifications.new(owner: @business, actor: @owner)
        notifications = customer_notification.budget_notifications

        refute_empty notifications
      end
    end

    context "#budget_threshold_banners" do
      test "returns empty array if api call raises exception" do
        mock_get_all_budgets_response_error
        notification = CustomerBudgetsNotifications.new(owner: @business)

        assert_empty notification.budget_threshold_banners(actor: @current_user)
      end

      test "returns array of BudgetThresholdBanner when there are valid budgets with banner" do
        mock_get_all_budgets_response(customer_id: @business.customer.id, target_type: CUSTOMER_TARGET, target_id: @business.customer.id, current_amount: 75.0, threshold_percentage: 0.75, threshold_alertable: true)

        customer_notification = CustomerBudgetsNotifications.new(owner: @business)
        banners = customer_notification.budget_threshold_banners(actor: @current_user)

        assert banners.present?
        assert_equal 1, banners.count
      end

      test "returns empty array when #budget_notifications returns empty array" do
        customer_notification = CustomerBudgetsNotifications.new(owner: @business)
        customer_notification.stubs(:budget_notifications).returns([])
        banners = customer_notification.budget_threshold_banners(actor: @current_user)

        assert_empty banners
      end

      test "returns empty array if the available budget banners have been dismissed" do
        mock_get_all_budgets_response(
          customer_id: @business.customer.id, target_type: CUSTOMER_TARGET, target_id: @business.customer.id, current_amount: 75.0,
          target_amount: 100.0, pricing_target_type: :SkuPricing, uuid: "1234",
          threshold_percentage: 75, threshold_alertable: true, times: 2
        )

        customer_notification = CustomerBudgetsNotifications.new(owner: @business)
        banners = customer_notification.budget_threshold_banners(actor: @current_user)

        # banner exists
        assert banners.present?

        # dismiss banner
        key = "billing_platform-budget_1234-100.0-threshold_75"
        product_tag = "billing_platform_SkuPricing"
        dismiss = Billing::Notifications::Dismissal.new(account: @business, actor_id: @current_user.id)
        dismiss.create(key, product_tag: product_tag)

        customer_notification = CustomerBudgetsNotifications.new(owner: @business)
        banners = customer_notification.budget_threshold_banners(actor: @current_user)

        # banner no longer exist
        assert_empty banners
      end
    end
  end
end
