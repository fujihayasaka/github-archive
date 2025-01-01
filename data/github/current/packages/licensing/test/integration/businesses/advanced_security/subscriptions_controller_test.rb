# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessesAdvancedSecuritySubscriptionsControllerHttpTest < GitHub::IntegrationTestCase
  skip_with_all_emus

  include HydroTestHelpers

  fixtures do
    @owner = create(:user, :zuora)
    @business = create(:business, :with_self_serve_payment, owners: [@owner])
    product_uuid = create(
      :billing_product_uuid,
      name: "GitHub Advanced Security",
      product_type: "github.advanced_security",
      product_key: "v0",
      billing_cycle: "month",
      zuora_product_rate_plan_id: "123abc",
      charges: [{
        "name" => "GitHub Advanced Security",
        "type" => "unit",
        "price" => 49,
        "billing_duration" => "month",
        "zuora_product_rate_plan_charge_id" => "8ad08e0183ac566c0183b3885d902c2f"
      }]
    )
    @advanced_security_subscription_item = Billing::SubscriptionItem.create(
      plan_subscription: @business.plan_subscription,
      subscribable: product_uuid,
      quantity: 1,
      customer: @business.customer,
    )
  end

  context "PUT /enterprises/:slug/settings/advanced_security/subscriptions, format: html" do
    test "schedules existing subscription for cancellation" do
      @business.subscribe_to_advanced_security(seats: 5, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      as @owner

      assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
        put "/enterprises/#{@business.to_param}/settings/advanced_security/subscriptions", xhr: true
      end

      @advanced_security_subscription_item.reload
      refute @advanced_security_subscription_item.cancelled?
      message = {
        category: "business_advanced_security_subscription",
        action: "cancel_subscription",
        label: "business_id:#{@business.id}",
      }
      assert_hydro_published_partial message, schema: "github.analytics.v0.Event"
      flash_message = "Your Advanced Security subscription has been successfully scheduled for cancellation."
      assert_equal flash_message, flash[:business_committers_success]
    end

    test "alert if subscription is already canceled" do
      @business.subscribe_to_advanced_security(seats: 5, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      as @owner
      @advanced_security_subscription_item.cancel!(actor: @owner, force: true)
      put "/enterprises/#{@business.to_param}/settings/advanced_security/subscriptions", xhr: true

      @advanced_security_subscription_item.reload
      assert @advanced_security_subscription_item.cancelled?
      assert_equal "This account is not subscribed to Advanced Security", flash[:business_committers_error]
    end

    test "not found if user is not authorized" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
      @business.set_advanced_security_seats_for_entity(actor: @owner, seats: 5)
      user = create(:user)
      @business.add_user_accounts([user.id])
      as user
      put "/enterprises/#{@business.to_param}/settings/advanced_security/subscriptions", xhr: true

      @advanced_security_subscription_item.reload
      refute @advanced_security_subscription_item.cancelled?
      assert_response_not_found
    end

  end if GitHub.billing_enabled?

  context "PUT /enterprises/:slug/settings/advanced_security/subscriptions, format: json" do
    test "schedules existing subscription for cancellation" do
      @business.subscribe_to_advanced_security(seats: 5, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      as @owner

      assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
        put "/enterprises/#{@business.to_param}/settings/advanced_security/subscriptions", xhr: true, format: :json
      end

      assert_response :success

      pending_change = @business.pending_subscription_item_changes.sole
      assert_equal({
        "success" => "Your Advanced Security subscription has been successfully scheduled for cancellation.",
        "newPendingCycleChange" => {
          "changeType" => "downgrade",
          "effectiveDate" => pending_change.active_on.in_time_zone(GitHub::Billing.timezone).as_json,
          "id" => pending_change.id,
          "isCancellation" => true,
          "isChangingDuration" => false,
          "isChangingSeats" => true,
          "newPrice" => "$0",
          "newSeatCount" => 0,
          "planDuration" => "month",
          "planDisplayName" => "GitHub Advanced Security",
        }
      }, JSON.parse(response.body))

      @advanced_security_subscription_item.reload
      refute @advanced_security_subscription_item.cancelled?
      message = {
        category: "business_advanced_security_subscription",
        action: "cancel_subscription",
        label: "business_id:#{@business.id}",
      }
      assert_hydro_published_partial message, schema: "github.analytics.v0.Event"
    end

    test "returns if subscription is already canceled" do
      @business.subscribe_to_advanced_security(seats: 5, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      as @owner
      @advanced_security_subscription_item.cancel!(actor: @owner, force: true)
      put "/enterprises/#{@business.to_param}/settings/advanced_security/subscriptions", xhr: true, format: :json

      assert_response :unprocessable_entity
      assert_equal({ "error" => "This account is not subscribed to Advanced Security" }, JSON.parse(response.body))

      @advanced_security_subscription_item.reload
      assert @advanced_security_subscription_item.cancelled?
    end
  end if GitHub.billing_enabled?
end
