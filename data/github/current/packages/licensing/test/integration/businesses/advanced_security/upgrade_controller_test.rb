# typed: true
# frozen_string_literal: true

require "test_helper"

class Businesses::AdvancedSecurity::UpgradeControllerTest < GitHub::IntegrationTestCase
  skip_with_all_emus

  include HydroTestHelpers

  fixtures do
    @owner = create :user, :with_trade_screening_record
    @business = create :business, :with_self_serve_payment, :with_trade_screening_record, owners: [@owner]
    @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
  end

  setup do
    enable_feature_flag(:live_sdn_screening)
  end

  context "GET /enterprises/:slug/settings/billing/advanced_security/upgrade" do
    test "has a seat stepper, billing info, payment options, and purchase button" do
      as @owner
      get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/upgrade"
      assert_select ".js-stepper"
      assert_test_selector "payment_information"
      assert_test_selector "billing_information"
      assert_test_selector "purchase_button"
      assert_response 200
    end

    test "trade screening cannot proceed component is shown when target has trade screening status" do
      @business.stubs(:perform_live_sdn_screening)
      @business.trade_screening_record.hit_in_review!

      as @owner
      get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/upgrade"

      assert_test_selector "trade-screening-cannot-proceed"
      refute_test_selector "payment-information-form"
    end

    test "trade screening cannot proceed component is shown when current user has trade screening status" do
      @owner.stubs(:perform_live_sdn_screening)
      @owner.trade_screening_record.hit_in_review!

      as @owner
      get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/upgrade"

      assert_test_selector "trade-screening-cannot-proceed"
      refute_test_selector "payment-information-form"
    end

    test "purchase button is disabled when the business has trade screening status" do
      @business.stubs(:perform_live_sdn_screening)
      @business.trade_screening_record.hit_in_review!

      as @owner
      get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/upgrade"

      assert_test_selector "purchase_button" do |button|
        assert button.attr("disabled")
      end
    end

    test "purchase button is disabled when the current sure has trade screening status" do
      @owner.stubs(:perform_live_sdn_screening)
      @owner.trade_screening_record.hit_in_review!

      as @owner
      get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/upgrade"

      assert_test_selector "purchase_button" do |button|
        assert button.attr("disabled")
      end
    end

    test "shows sales tax information for businesses that should be charged sales tax" do
      Business.any_instance.expects(:display_sales_tax_on_checkout?).returns(true)

      as @owner
      get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/upgrade"

      assert_response :success
      assert_includes response.body, "Due today"
      assert_test_selector "sales-tax-label"
      assert_test_selector "sales-tax-value"
    end

    test "does not show sales tax information for businesses that should not be charged sales tax" do
      Business.any_instance.expects(:display_sales_tax_on_checkout?).returns(false)

      as @owner
      get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/upgrade"

      assert_response :success
      assert_includes response.body, "Due today"
      refute_test_selector "sales-tax-label"
      refute_test_selector "sales-tax-value"
    end

    test "user cannot edit billing information when trade screening profile status is retry" do
      business = create(:business, :with_self_serve_payment, :with_trade_screening_record, owners: [@owner])
      business.customer.update_attribute(:billing_type, "card")
      business.trade_screening_record.retry!
      business.stubs(:perform_live_sdn_screening)

      as @owner
      get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/upgrade"

      assert_response :success
      assert_test_selector "billing_information"
      assert_select ".js-billing-settings-billing-information-edit-button" do |button|
        assert button.attr("hidden")
      end
    end

    context "suggested committers" do
      test "renders banner when converting from trial and consumed seats > 0" do
        as @owner
        @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
        )
        AdvancedSecurityLicense.any_instance.stubs(:consumed_seats).returns(10)

        get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/upgrade"

        assert_response 200
        assert_test_selector "ghas_suggested_committers"
      end

      test "does not render banner when there are 0 consumed seats" do
        as @owner
        @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
        )
        AdvancedSecurityLicense.any_instance.stubs(:consumed_seats).returns(0)

        get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/upgrade"

        assert_response 200
        refute_test_selector "ghas_suggested_committers"
      end

      test "does not render banner when not coming from trial" do
        as @owner
        AdvancedSecurityLicense.any_instance.stubs(:consumed_seats).returns(10)

        get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/upgrade"

        assert_response 200
        refute_test_selector "ghas_suggested_committers"
      end

      test "prefills suggested seats" do
        as @owner
        @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
        )
        AdvancedSecurityLicense.any_instance.stubs(:consumed_seats).returns(10)

        get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/upgrade"

        assert_response 200
        assert_select ".unstyled-new-seats", text: "10 committers"
      end
    end
  end

  context "GET XHR /enterprises/:slug/settings/billing/advanced_security/upgrade" do
    test "returns price preview" do
      as @owner
      get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/upgrade", xhr: true, params: { seats: "10" }
      assert_response :success
      json = JSON.parse(response.body)
      assert_equal({
        "seats" => 10,
        "selectors" => {
          ".unstyled-payment-due" => "$490.00",
          ".unstyled-new-seats" => "10 committers",
          ".unstyled-label" => "committers",
        }
      }, json)
    end

    test "handles min values" do
      as @owner
      get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/upgrade", xhr: true, params: { seats: "-1" }
      assert_response :success
      json = JSON.parse(response.body)
      assert_equal({
        "seats" => 1,
        "selectors" => {
          ".unstyled-payment-due" => "$49.00",
          ".unstyled-new-seats" => "1 committer",
          ".unstyled-label" => "committer"
        }
      }, json)
    end

    test "handles max values" do
      as @owner
      get "/enterprises/#{@business.to_param}/settings/billing/advanced_security/upgrade", xhr: true, params: { seats: "999999999" }
      assert_response :success
      json = JSON.parse(response.body)
      assert_equal({
        "seats" => 1000,
        "selectors" => {
          ".unstyled-payment-due" => "$49,000.00",
          ".unstyled-new-seats" => "1000 committers",
          ".unstyled-label" => "committers"
        }
      }, json)
    end
  end

  context "PUT /enterprises/:slug/settings/billing/advanced_security/subscribe" do
    test "shows error if seats is below 1" do
      @business.customer.update_attribute(:billing_type, "card")
      as @owner
      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/subscribe",
        params: { seats: -20 }
      assert @business.eligible_for_self_serve_advanced_security?
      assert_equal "Number of committers must be greater than 0.", flash[:error]

      assert_response :redirect
      assert_redirected_to settings_billing_enterprise_path(@business)
    end

    test "shows error if above max seats" do
      @business.customer.update_attribute(:billing_type, "card")
      @business.set_custom_seat_limit_for_advanced_security_upgrades(500, User.ghost)
      @business.set_custom_seat_limit_for_upgrades(1000, User.ghost)
      as @owner
      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/subscribe",
        params: { seats: 501 }
      assert @business.eligible_for_self_serve_advanced_security?
      assert_equal "Number of committers must be fewer than 500.", flash[:error]

      assert_response :redirect
      assert_redirected_to settings_billing_enterprise_path(@business)
    end

    test "not found if user is not authorized" do
      @business.customer.update_attribute(:billing_type, "card")
      user = create(:user)
      @business.add_user_accounts([user.id])
      as user
      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/subscribe",
        params: { seats: 1_000_001 }
      assert_response :not_found
    end

    test "displays a warning and redirects to enterprise payment information when business has invalid trade screening record status" do
      business = create(:business, :with_self_serve_payment, :with_trade_screening_record, owners: [@owner])
      business.trade_screening_record.hit_in_review!
      business.stubs(:perform_live_sdn_screening)

      as @owner
      put "/enterprises/#{business.to_param}/settings/billing/advanced_security/subscribe",
        params: { seats: 5 }

      assert_response :redirect
      assert_redirected_to settings_billing_tab_enterprise_url(tab: :payment_information)
      assert flash[:trade_screening_generic_notice]
    end

    test "creates subscription when all parameters are valid" do
      @business.customer.update_attribute(:billing_type, "card")
      as @owner

      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/subscribe",
        params: { seats: 5 }

      assert_redirected_to settings_billing_enterprise_path(@business)
      assert @business.has_active_monthly_advanced_security_subscription?
      assert @business.advanced_security_seats_for_entity, 5
      assert_equal "Successfully added 5 GitHub Advanced Security Committers.", flash[:success]

      message = {
        category: "business_advanced_security_subscription",
        action: "subscribe_to_advanced_security",
        label: "business_id:#{@business.id},seats:5,converted_from_trial:false",
      }
      assert_hydro_published_partial message, schema: "github.analytics.v0.Event"
    end

    test "creates subscription when all parameters are valid and has an active ghas trial" do

      @business.customer.update_attribute(:billing_type, "card")

      result = @business.subscribe_to_advanced_security_trial(
        actor: @owner,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
      )
      assert result.ok?

      as @owner

      put "/enterprises/#{@business.to_param}/settings/billing/advanced_security/subscribe",
        params: { seats: 7 }

      assert_redirected_to settings_billing_enterprise_path(@business)
      assert @business.has_active_monthly_advanced_security_subscription?
      assert @business.advanced_security_seats_for_entity, 7
      assert_equal "Successfully added 7 GitHub Advanced Security Committers.", flash[:success]

      message = {
        category: "business_advanced_security_subscription",
        action: "subscribe_to_advanced_security",
        label: "business_id:#{@business.id},seats:7,converted_from_trial:true",
      }
      assert_hydro_published_partial message, schema: "github.analytics.v0.Event"
    end
  end
end if GitHub.billing_enabled?
