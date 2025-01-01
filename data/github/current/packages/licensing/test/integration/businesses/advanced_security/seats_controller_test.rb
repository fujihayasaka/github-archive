# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessesAdvancedSecuritySeatsControllerHttpTest < GitHub::IntegrationTestCase
  skip_with_all_emus

  include HydroTestHelpers
  include TurboghasHelpers

  fixtures do
    @owner = create :user, :with_trade_screening_record
    @business = create(:business, :with_self_serve_payment, owners: [@owner])
    @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
  end

  context "GET /enterprises/:slug/settings/billing/advanced_security/seat_price" do
    test "responds with a JSON object on XHR GET" do
      travel_to("2020-08-22 10:00:00 PDT") do
        @business.subscribe_to_advanced_security(seats: 1, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        as @owner
        get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/seat_price", params: { seats: "14" }, xhr: true
        json = JSON.parse(response.body)

        assert_response :success

        assert_equal({
          "total_seats" => 14,
          "old_seats" => 1,
          "current_price" => "$686.00",
          "payment_increase" => "$637.00",
          "payment_decrease" => nil,
          "payment_due" => "$637.00",
          "payment_due_notice" => "Your next payment of 686.00 will be due on August 22, 2020",
          "sales_tax_notice" => " ",
          }, json)
      end
    end

    test "handles decrease" do
      travel_to("2020-08-22 10:00:00 PDT") do
        @business.subscribe_to_advanced_security(seats: 10, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        as @owner
        get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/seat_price", params: { seats: "2" }, xhr: true
        json = JSON.parse(response.body)

        assert_response :success

        assert_equal({
          "total_seats" => 2,
          "old_seats" => 10,
          "current_price" => "$98.00",
          "payment_increase" => nil,
          "payment_decrease" => "$392.00",
          "payment_due" => "—",
          "payment_due_notice" => "Your changes will take effect on August 22, 2020",
          "sales_tax_notice" => " ",
          }, json)
      end
    end

    test "handles negative values" do
      @business.subscribe_to_advanced_security(seats: 1, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      as @owner
      get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/seat_price", params: { seats: "-1" }, xhr: true
      json = JSON.parse(response.body)

      assert_response :success

      assert_equal({
        "total_seats" => 1,
        "old_seats" => 1,
        "current_price" => "$49.00",
        "payment_increase" => nil,
        "payment_decrease" => nil,
        "payment_due" => "—",
        "payment_due_notice" => " ",
        "sales_tax_notice" => " ",
        }, json)
    end

    test "handles max values" do
      travel_to("2020-08-22 10:00:00 PDT") do
        @business.subscribe_to_advanced_security(seats: 1, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

        as @owner
        get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/seat_price", params: { seats: "2000" }, xhr: true
        json = JSON.parse(response.body)

        assert_response :success

        assert_equal({
          "total_seats" => 301,
          "old_seats" => 1,
          "current_price" => "$14,749.00",
          "payment_increase" => "$14,700.00",
          "payment_decrease" => nil,
          "payment_due" => "$14,700.00",
          "payment_due_notice" => "Your next payment of 14749.00 will be due on August 22, 2020",
          "sales_tax_notice" => " ",
          }, json)
      end
    end

    test "includes sales tax information when the business should be charged sales tax and new seats are being added" do
      Business.any_instance.expects(:display_sales_tax_on_checkout?).returns(true)
      travel_to("2020-08-22 10:00:00 PDT") do
        @business.subscribe_to_advanced_security(seats: 1, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        as @owner
        get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/seat_price", params: { seats: "14" }, xhr: true
        json = JSON.parse(response.body)

        assert_response :success

        assert_subset_hash({
          "sales_tax_notice" => "Sales tax will be added to your invoice",
          }, json)
      end
    end

    test "does not include sales tax information when the business should be charged sales tax and no new seats are being added" do
      Business.any_instance.expects(:display_sales_tax_on_checkout?).returns(true)
      travel_to("2020-08-22 10:00:00 PDT") do
        @business.subscribe_to_advanced_security(seats: 10, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        as @owner
        get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/seat_price", params: { seats: "10" }, xhr: true
        json = JSON.parse(response.body)

        assert_response :success

        assert_subset_hash({
          "sales_tax_notice" => " ",
          }, json)
      end
    end
  end if GitHub.billing_enabled?

  context "PUT /enterprises/:slug/settings/billing/advanced_security/change_seats, format: html" do
    test "updates GHAS number of seats if GHAS is enabled" do
      @business.subscribe_to_advanced_security(seats: 10, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      assert_equal @business.advanced_security_seats_for_entity, 10
      as @owner
      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/change_seats",
        params: { seats: 50 }
      @business.reload
      assert_equal 50, @business.advanced_security_seats_for_entity

      message = {
        category: "business_advanced_security_subscription",
        action: "upgrade_self_serve_seats",
        label: "business_id:#{@business.id},old_seats:10,new_seats:50",
      }
      assert_hydro_published_partial message, schema: "github.analytics.v0.Event"
    end

    test "creates a pending change when the GHAS number of seats is downgraded if GHAS is enabled" do
      @business.subscribe_to_advanced_security(seats: 30, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert_equal @business.advanced_security_seats_for_entity, 30
      as @owner
      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/change_seats",
        params: { seats: 20 }
      @business.reload

      message = {
        category: "business_advanced_security_subscription",
        action: "downgrade_self_serve_seats",
        label: "business_id:#{@business.id},old_seats:30,new_seats:20",
      }
      assert_hydro_published_partial message, schema: "github.analytics.v0.Event"

      pending_subscription_item_change = @business.pending_subscription_item_changes.sole
      assert_equal 20, pending_subscription_item_change.quantity
      assert_equal @advanced_security_product_uuid.id, pending_subscription_item_change.subscribable_id
    end

    test "does not update GHAS number of seats if number of seats is above max allowed" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
      assert_equal 0, @business.advanced_security_seats_for_entity
      as @owner
      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/change_seats",
        params: { seats: 301 }
      @business.reload
      assert_equal @business.advanced_security_seats_for_entity, 0
    end

    test "does not remove GHAS number of seats if number of seats is above max allowed" do
      @business.subscribe_to_advanced_security(seats: 700, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      assert_equal @business.advanced_security_seats_for_entity, 700
      as @owner
      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/change_seats",
        params: { seats: 299 }
      @business.reload
      assert_equal @business.advanced_security_seats_for_entity, 700
      assert_equal "You can only add or remove up to 300 committers at a time.", flash[:business_committers_error]
    end

    test "does not update GHAS number of seats if user is not authorized" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
      assert_equal 0, @business.advanced_security_seats_for_entity
      user = create(:user)
      @business.add_user_accounts([user.id])
      as user
      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/change_seats",
        params: { seats: 2 }
      @business.reload
      assert_response :not_found
    end

    test "does not update GHAS number of seats if lower than active committers" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
      assert_equal 0, @business.advanced_security_seats_for_entity

      stub_turboghas_summary(maximum_committers: 3, active_committers: 3)

      as @owner
      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/change_seats",
        params: { seats: 2 }
      @business.reload
      assert_equal 0, @business.advanced_security_seats_for_entity
      assert_equal "Number of committers must be greater than current active committers.", flash[:business_committers_error]
    end

    test "does not updates GHAS number of seats if GHAS is not enabled" do
      @business.mark_advanced_security_as_not_purchased_for_entity(actor: @owner)
      assert_equal @business.advanced_security_seats_for_entity, 0
      as @owner
      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/change_seats",
        params: { seats: 50 }
      @business.reload
      assert_equal @business.advanced_security_seats_for_entity, 0
      refute @business.advanced_security_purchased_for_entity?
    end

    test "does not update GHAS number of seats when user has trade screening status" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
      assert_equal @business.advanced_security_seats_for_entity, 0
      @owner.trade_screening_record.hit_in_review!
      @owner.stubs(:perform_live_sdn_screening)

      enable_feature_flag(:live_sdn_screening)

      as @owner
      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/change_seats",
        params: { seats: 50 }

      assert_response :redirect
      assert_redirected_to settings_billing_tab_enterprise_url(tab: :payment_information)
      assert flash[:trade_screening_generic_notice]
    end
  end if GitHub.billing_enabled?

  context "PUT /enterprises/:slug/settings/billing/advanced_security/change_seats, format: json" do
    test "updates GHAS number of seats if GHAS is enabled" do
      @business.subscribe_to_advanced_security(seats: 10, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      assert_equal @business.advanced_security_seats_for_entity, 10
      as @owner
      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/change_seats",
        params: { seats: 50 },
        format: :json

      assert_response :ok
      assert_equal({
        "success" => "Number of GitHub Advanced Security Committers updated to 50.",
        "newPayment" => "$2,450.00",
        "newSeatCount" => 50,
        "newPendingCycleChange" => nil,
      }, JSON.parse(response.body))

      @business.reload
      assert_equal 50, @business.advanced_security_seats_for_entity

      message = {
        category: "business_advanced_security_subscription",
        action: "upgrade_self_serve_seats",
        label: "business_id:#{@business.id},old_seats:10,new_seats:50",
      }
      assert_hydro_published_partial message, schema: "github.analytics.v0.Event"
    end

    test "creates a pending change when the GHAS number of seats is downgraded if GHAS is enabled" do
      @business.subscribe_to_advanced_security(seats: 30, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert_equal @business.advanced_security_seats_for_entity, 30
      as @owner
      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/change_seats",
        params: { seats: 20 },
        format: :json

      @business.reload

      message = {
        category: "business_advanced_security_subscription",
        action: "downgrade_self_serve_seats",
        label: "business_id:#{@business.id},old_seats:30,new_seats:20",
      }
      assert_hydro_published_partial message, schema: "github.analytics.v0.Event"

      pending_subscription_item_change = @business.pending_subscription_item_changes.sole
      assert_equal 20, pending_subscription_item_change.quantity
      assert_equal @advanced_security_product_uuid.id, pending_subscription_item_change.subscribable_id

      assert_response :ok
      assert_equal({
        "success" => "Downgrade to 20 GitHub Advanced Security Committers scheduled.",
        "newPayment" => "$980.00",
        "newSeatCount" => 20,
        "newPendingCycleChange" => {
          "changeType" => "downgrade",
          "effectiveDate" => pending_subscription_item_change.active_on.in_time_zone(GitHub::Billing.timezone).as_json,
          "id" => pending_subscription_item_change.id,
          "isCancellation" => false,
          "isChangingDuration" => false,
          "isChangingSeats" => true,
          "newPrice" => "$980",
          "newSeatCount" => 20,
          "planDuration" => "month",
          "planDisplayName" => "GitHub Advanced Security",
        },
      }, JSON.parse(response.body))
    end

    test "does not update GHAS number of seats if number of seats is above max allowed" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
      assert_equal 0, @business.advanced_security_seats_for_entity
      as @owner
      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/change_seats",
        params: { seats: 301 },
        format: :json

      assert_response :unprocessable_entity
      assert_equal({
        "error" => "You can only add or remove up to 300 committers at a time.",
      }, JSON.parse(response.body))
      @business.reload
      assert_equal @business.advanced_security_seats_for_entity, 0
    end

    test "does not update GHAS number of seats if lower than active committers" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
      assert_equal 0, @business.advanced_security_seats_for_entity

      stub_turboghas_summary(maximum_committers: 3, active_committers: 3)

      as @owner
      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/change_seats",
        params: { seats: 2 },
        format: :json

      assert_response :unprocessable_entity
      assert_equal({
        "error" => "Number of committers must be greater than current active committers.",
      }, JSON.parse(response.body))

      @business.reload
      assert_equal 0, @business.advanced_security_seats_for_entity
    end
  end if GitHub.billing_enabled?
end
