# typed: true
# frozen_string_literal: true

require "test_helper"

class PendingSubscriptionItemChanges::FreeTrialCancellationsControllerTest < GitHub::IntegrationTestCase
  fixtures do
    @mona = create :credit_card_user, login: "mona"
    @copilot_monthly_product = create(:billing_product_uuid, :copilot, billing_cycle: :month)
    @plan_subscription = create(:billing_plan_subscription, user: @mona)
    @subscription_item = create \
      :billing_subscription_item,
      plan_subscription: @plan_subscription,
      subscribable: @copilot_monthly_product,
      free_trial_ends_on: GitHub::Billing.today + 60.days
    @cancellation_change = create \
      :billing_pending_subscription_item_change,
      account: @mona,
      plan_subscription: @plan_subscription,
      subscribable: @copilot_monthly_product,
      free_trial: true,
      quantity: 0
  end

  context "#update" do
    test "cancels a free trial cancellation" do
      as @mona
      put "/pending_subscription_item_changes/#{@cancellation_change.id}/free_trial_cancellation"
      assert_response :redirect

      @cancellation_change.reload

      refute @cancellation_change.free_trial_cancellation?
      assert_equal @subscription_item.quantity, @cancellation_change.quantity
      assert_match "Successfully resumed your free trial", flash[:notice]
    end

    test "returns any errors on the subscription change if present" do
      errors = stub("errors", full_messages: ["error message"], clear: nil, empty?: false, any?: true)
      Billing::PendingSubscriptionItemChange.any_instance.stubs(:errors).returns(errors)

      as @mona
      put "/pending_subscription_item_changes/#{@cancellation_change.id}/free_trial_cancellation"
      assert_response :redirect

      assert_match "error message", flash[:error]
    end
  end
end if GitHub.billing_enabled?
