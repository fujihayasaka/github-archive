# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessesEnterpriseLicensingControllerHttpTest < GitHub::IntegrationTestCase
  include BusinessTestHelpers
  include TurboghasHelpers
  include GitHub::ReactPayloadHelper

  fixtures do
    @owner = create(:user)
    @billing_manager = create(:user)
    @member = create(:user)
    @organization = create(:organization)
    @organization.add_member(@member)
    @business = create(:business, owners: [@owner], organizations: [@organization])
    @business.billing.add_manager(@billing_manager, actor: @owner)
    create(:billing_product_uuid, :advanced_security)
    create(:billing_product_uuid, :advanced_security, :yearly)
  end

  setup do
    disable_feature_flag(:enterprise_licensing_feedback_survey, @business)
    disable_feature_flag(:enterprise_licensing_advanced_security)
  end

  context "GET /enterprises/:slug/enterprise_licensing", skip_with_all_emus: true do
    if GitHub.billing_enabled?
      test_business_access do
        get "/enterprises/#{@business.slug}/enterprise_licensing"
      end

      test "allows owners to see the licensing information" do
        as @owner

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_response :success
      end

      test "allows billing managers to see the licensing information" do
        as @billing_manager

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_response :success
      end

      test "does not include link to enterprise people page for billing managers" do
        as @billing_manager
        get "/enterprises/#{@business}/enterprise_licensing"
        assert_response :success
        refute_select "[data-test-selector='view-details-people-link']"
      end

      test "does not blow up for billing managers who are also site admins when enterprise installations and uploads exist" do
        installation = create(:enterprise_installation, owner: @business)
        create(:enterprise_installation_user_accounts_upload, business: @business, enterprise_installation: installation)
        site_admin_and_billing_manager = create(:staff_admin_user)
        @business.billing.add_manager(site_admin_and_billing_manager, actor: @owner)

        as site_admin_and_billing_manager

        get "/enterprises/#{@business.slug}/enterprise_licensing"
        assert_response :success
      end

      test "works when there are enterprise installations without uploads" do
        installation = create(:enterprise_installation, owner: @business)
        site_admin_and_billing_manager = create(:staff_admin_user)
        @business.billing.add_manager(site_admin_and_billing_manager, actor: @owner)

        as site_admin_and_billing_manager

        get "/enterprises/#{@business.slug}/enterprise_licensing"
        assert_response :success
      end

      test "does not blow up for businesses with advanced security enabled" do
        @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        @business.set_advanced_security_seats_for_entity(seats: 42, actor: @owner)

        as @owner

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-status"
        refute_test_selector "advanced-security-license-promo"
        refute_test_selector "advanced-security-license-self-serve"

        @business.customer.azure_subscription_id = "12345"
        @business.mark_advanced_security_as_metered_for_entity(actor: @owner)

        as @owner

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-status"
        refute_test_selector "advanced-security-license-promo"
        refute_test_selector "advanced-security-license-self-serve"
      end

      test "shows sales-serve if manually enabled in stafftools for a manual sales trial" do
        business = create :business, :with_self_serve_payment, owners: [@owner]

        business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        business.set_advanced_security_seats_for_entity(seats: 10, actor: @owner)

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-status"
        refute_test_selector "advanced-security-license-promo"
        refute_test_selector "advanced-security-license-self-serve"
      end

      test "advertises advanced security if a customer is eligible for it" do
        business = create :business, :with_self_serve_payment, owners: [@owner]

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        refute_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-status"
        assert_test_selector "advanced-security-license-promo"
        refute_test_selector "advanced-security-license-self-serve"
        assert_test_selector "buy-ghas-self-serve", text: "Buy Advanced Security" do |button|
          assert_includes button.attr("class").value, "btn-sm btn"
        end
      end

      test "advertises advanced security trial if a customer is eligible for it" do
        business = create :business, :with_self_serve_payment, owners: [@owner]

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        refute_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-status"
        assert_test_selector "advanced-security-license-promo"
        refute_test_selector "advanced-security-license-self-serve"
        assert_test_selector "ghas-start-free-trial"
        assert_test_selector "buy-ghas-self-serve", text: "Buy Advanced Security" do |button|
          assert_includes button.attr("class").value, "btn-sm btn f6"
        end
      end

      test "advertises advanced security trial if a customer is eligible for it with an active Enterprise trial" do
        business = create :business, :with_self_serve_payment, owners: [@owner]

        business.update_attribute :trial_expires_at, ::Billing::EnterpriseCloudTrial.trial_length.from_now

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        refute_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-status"
        assert_test_selector "advanced-security-license-promo"
        refute_test_selector "advanced-security-license-self-serve"
        assert_test_selector "ghas-start-free-trial"
        refute_test_selector "buy-ghas-self-serve", text: "Buy Advanced Security"
      end

      test "does not advertise advanced security trial, if not enough trial days are left" do
        business = create :business, :with_self_serve_payment, owners: [@owner]

        jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
        jan_20th = GitHub::Billing.date_in_timezone Date.parse("2023-01-20")

        travel_to jan_1st do
          business.update_attribute :trial_expires_at, ::Billing::EnterpriseCloudTrial.trial_length.from_now
        end

        travel_to jan_20th do
          as @owner

          get "/enterprises/#{business.slug}/enterprise_licensing"

          assert_response :success
          refute_test_selector "advanced-security-license-sales-serve"
          refute_test_selector "advanced-security-license-status"
          refute_test_selector "advanced-security-license-promo"
          refute_test_selector "advanced-security-license-self-serve"
        end
      end

      test "displays pending seat change status message if GHAS renewal is in progress and 'upgrade now' was selected" do
        business = create :business, :with_self_serve_payment, owners: [@owner]
        enable_feature_flag(:ghe_sales_serve_renewals, business)

        business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        business.set_advanced_security_seats_for_entity(seats: 10, actor: @owner)
        change_request = create(:sales_serve_subscription_change_request, customer: business.customer)
        create(:sales_serve_subscription_change_request_item, :github_advanced_security, change_request: change_request, quantity: 170, status: :pending, change_type: :update)

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        assert_test_selector "advanced-security-license-status", text: /Your upgrade of 160 GitHub Advanced Security committers is being processed/
      end

      test "does not display the pending seat change status message if GHAS renewal is in progress and 'upgrade now' was not selected" do
        business = create :business, :with_self_serve_payment, owners: [@owner]
        enable_feature_flag(:ghe_sales_serve_renewals, business)

        business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        business.set_advanced_security_seats_for_entity(seats: 10, actor: @owner)
        change_request = create(:sales_serve_subscription_change_request, customer: business.customer)
        create(:sales_serve_subscription_change_request_item, :github_advanced_security, change_request: change_request, quantity: 170, status: :pending, change_type: :renewal)

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-status"
      end

      test "doesn't display pending seat change status for GHAS message if GHE renewal is in progress" do
        business = create :business, :with_self_serve_payment, owners: [@owner]
        enable_feature_flag(:ghe_sales_serve_renewals, business)

        business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        business.set_advanced_security_seats_for_entity(seats: 10, actor: @owner)
        change_request = create(:sales_serve_subscription_change_request, customer: business.customer)
        create(:sales_serve_subscription_change_request_item, :github_enterprise, change_request: change_request, quantity: 170, status: :pending, change_type: :renewal)

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-status"
      end

      test "doesn't display pending seat change status for GHAS message if GHE update now is in progress but GHAS is a renewal" do
        business = create :business, :with_self_serve_payment, owners: [@owner]
        enable_feature_flag(:ghe_sales_serve_renewals, business)

        business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        business.set_advanced_security_seats_for_entity(seats: 10, actor: @owner)
        change_request = create(:sales_serve_subscription_change_request, customer: business.customer)
        create(:sales_serve_subscription_change_request_item, :github_enterprise, change_request: change_request, quantity: 170, status: :pending, change_type: :update)
        create(:sales_serve_subscription_change_request_item, :github_advanced_security, change_request: change_request, quantity: 170, status: :pending, change_type: :renewal)

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-status"
      end

      test "doesn't display pending seat change status message if GHAS renewal is in progress and seat change is negative" do
        business = create :business, :with_self_serve_payment, owners: [@owner]
        business.customer.update!(billing_end_date: 29.days.from_now, billing_type: "invoice")
        enable_feature_flag(:ghe_sales_serve_renewals, business)

        business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        business.set_advanced_security_seats_for_entity(seats: 10, actor: @owner)
        change_request = create(:sales_serve_subscription_change_request, customer: business.customer)
        create(:sales_serve_subscription_change_request_item, :github_advanced_security, change_request: change_request, quantity: 5, status: :pending, change_type: :renewal)

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-status"
      end

      test "doesn't display pending seat change status message if renewal is in progress for GHE downgrade" do
        business = create :business, :with_self_serve_payment, owners: [@owner]
        business.customer.update!(billing_end_date: 29.days.from_now, billing_type: "invoice")
        enable_feature_flag(:ghe_sales_serve_renewals, business)

        business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        business.set_advanced_security_seats_for_entity(seats: 10, actor: @owner)
        change_request = create(:sales_serve_subscription_change_request, customer: business.customer)
        create(:sales_serve_subscription_change_request_item, :github_enterprise, change_request: change_request, quantity: 5, status: :pending, change_type: :renewal)

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-status"
      end

      test "doesn't display seat change failed status message if renewal is in failed but not for GHAS" do
        business = create :business, :with_self_serve_payment, owners: [@owner]
        enable_feature_flag(:ghe_sales_serve_renewals, business)

        business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        business.set_advanced_security_seats_for_entity(seats: 10, actor: @owner)
        request = create(:sales_serve_subscription_change_request, customer: business.customer)
        request.items << create(:sales_serve_subscription_change_request_item, :github_enterprise, quantity: 170, status: :error, change_type: :renewal)

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-status"
      end

      test "displays seat change failed status message if GHAS renewal is in failed state" do
        business = create :business, :with_self_serve_payment, owners: [@owner]
        enable_feature_flag(:ghe_sales_serve_renewals, business)

        business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        business.set_advanced_security_seats_for_entity(seats: 10, actor: @owner)
        request = create(:sales_serve_subscription_change_request, customer: business.customer)
        request.items << create(:sales_serve_subscription_change_request_item, :github_advanced_security, quantity: 170, status: :error, change_type: :renewal)

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        assert_test_selector "advanced-security-license-status", text: /Your GitHub Advanced Security upgrade failed, please contact sales./
      end

      test "displays contact sales button if GHAS renewal is in failed state" do
        business = create :business, :with_self_serve_payment, owners: [@owner]
        business.customer.update!(billing_type: "invoice")
        enable_feature_flag(:ghe_sales_serve_renewals, business)
        enable_feature_flag(:sales_managed_subscription_self_serve_eligible_override, business)

        business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        business.set_advanced_security_seats_for_entity(seats: 10, actor: @owner)
        request = create(:sales_serve_subscription_change_request, customer: business.customer)
        request.items << create(:sales_serve_subscription_change_request_item, :github_advanced_security, quantity: 170, status: :error, change_type: :renewal)

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        assert_test_selector "licensing_component_description", text: /Contact sales/, href: /\/renewals-help/
      end

      test "displays pending seat change status message if mid-cycle upgrade is in progress if GHAS change" do
        business = create :business, :with_self_serve_payment, owners: [@owner]
        enable_feature_flag(:ghe_sales_serve_renewals, business)

        business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        business.set_advanced_security_seats_for_entity(seats: 10, actor: @owner)
        change_request = create(:sales_serve_subscription_change_request, customer: business.customer)
        create(:sales_serve_subscription_change_request_item, :github_advanced_security, change_request: change_request, quantity: 170, status: :pending, change_type: :update)

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        assert_test_selector "advanced-security-license-status", text: /Your upgrade of 160 GitHub Advanced Security committers is being processed./
      end

      test "doesn't display pending mid-cycle when upgrade is in progress for GHE" do
        business = create :business, :with_self_serve_payment, owners: [@owner]
        enable_feature_flag(:ghe_sales_serve_renewals, business)

        business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        business.set_advanced_security_seats_for_entity(seats: 10, actor: @owner)
        change_request = create(:sales_serve_subscription_change_request, customer: business.customer)
        create(:sales_serve_subscription_change_request_item, :github_enterprise, change_request: change_request, quantity: 170, status: :pending, change_type: :update)

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-status"
      end

      test "displays pending seat change status message if mid-cycle GHAS upgrade is in progress and seat change is negative" do
        business = create :business, :with_self_serve_payment, owners: [@owner]
        business.customer.update!(billing_end_date: 29.days.from_now, billing_type: "invoice")
        enable_feature_flag(:ghe_sales_serve_renewals, business)

        business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        business.set_advanced_security_seats_for_entity(seats: 10, actor: @owner)
        change_request = create(:sales_serve_subscription_change_request, customer: business.customer)
        create(:sales_serve_subscription_change_request_item, :github_advanced_security, change_request: change_request, quantity: 5, status: :pending, change_type: :update)

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        assert_test_selector "advanced-security-license-status", text: /Your GitHub Advanced Security upgrade is being processed./
      end

      test "doesn't display pending seat change status message if mid-cycle GHE upgrade is in progress and seat change is negative" do
        business = create :business, :with_self_serve_payment, owners: [@owner]
        business.customer.update!(billing_end_date: 29.days.from_now, billing_type: "invoice")
        enable_feature_flag(:ghe_sales_serve_renewals, business)

        business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        business.set_advanced_security_seats_for_entity(seats: 10, actor: @owner)
        change_request = create(:sales_serve_subscription_change_request, customer: business.customer)
        create(:sales_serve_subscription_change_request_item, :github_enterprise, change_request: change_request, quantity: 5, status: :pending, change_type: :update)

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-status"
      end

      test "can manage advanced security seats if a customer is eligible for it" do
        business = create :business, :with_self_serve_payment, owners: [@owner]
        business.subscribe_to_advanced_security(seats: 42, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success

        refute_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-status"
        refute_test_selector "advanced-security-license-promo"
        assert_test_selector "advanced-security-license-self-serve"
      end

      test "cannot edit seats when self-serve is in dunning" do
        business = create :business, :with_self_serve_payment, owners: [@owner]
        business.subscribe_to_advanced_security(seats: 42, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

        create :manual_dunning_period, :with_business, customer: business.customer
        business.increment_billing_attempts
        business.save!
        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success

        assert_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-status"
        refute_test_selector "advanced-security-license-promo"
        refute_test_selector "advanced-security-license-self-serve"
      end

      test "does not render enterprise server licensing and instances views for trial metered plan business" do
        @business.update_attribute :trial_expires_at, 1.day.from_now
        @business.customer.update metered_plan: true
        assert_predicate @business.reload, :metered_plan?
        assert @business.metered_ghec_trial?
        refute @business.metered_ghes_eligible?

        as @owner
        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_response :success
        refute_select "react-partial[partial-name=metered-enterprise-server-licenses]"
        refute_test_selector "enterprise_server_licenses"
        refute_test_selector "enterprise_server_instances"
      end

      test "does not render enterprise server licensing and instances views for copilot-only business" do
        @business.customer.update metered_plan: true
        @business.update seats_plan_type: :basic
        @business.reload

        assert business.metered_plan?
        assert business.metered_ghes_eligible?
        assert business.seats_plan_basic?

        as @owner
        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_response :success
        refute_select "react-partial[partial-name=metered-enterprise-server-licenses]"
        refute_test_selector "enterprise_server_licenses"
        refute_test_selector "enterprise_server_instances"
      end

      test "renders metered ghes partials for non-trial metered plan business" do
        @business.customer.update metered_plan: true
        assert_predicate business.reload, :metered_plan?
        refute business.metered_ghec_trial?
        assert business.metered_ghes_eligible?
        mock_licensify_sdlc_licensee_ids(@business.customer.id, [@member.id, @owner.id])

        ghes_license = create(:licensing_ghes_license, business: business, seats: 0)

        as @owner
        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        refute_test_selector "enterprise_server_licenses"
        assert_test_selector "enterprise_server_instances"

        embedded_data = get_react_partial_embedded_json("metered-enterprise-server-licenses")

        expected_props = {
          business: {
            slug: business.slug,
          },
          serverLicenses: [
            ghes_license.as_json(only: [:reference_number, :seats, :expires_at], root: false)
          ],
          consumedEnterpriseLicenses: 2,
        }.as_json

        assert_equal embedded_data["props"], expected_props
        assert_equal embedded_data["props"]["serverLicenses"].length, 1
      end

      test "renders licensing-enterprise-overview partial if customer is metered" do
        @business.customer.update(metered_plan: true)
        summary = ::Licensify::Services::V1::ProductLicenseeTypeLicenseStatusSummary.new(
          count: 2,
          licenseStatus: :LICENSE_STATUS_ACTIVE,
          licenseeType: :LICENSEE_TYPE_USER,
          product: :PRODUCT_SDLC,
        )
        mock_licensify_customer_usage_summary(@business.customer.id, [summary])

        as @owner
        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_select "react-partial[partial-name=licensing-enterprise-overview]"

        embedded_data = get_react_partial_embedded_json("licensing-enterprise-overview")

        assert_equal embedded_data["props"]["slug"], business.slug
        assert_equal embedded_data["props"]["ghe"]["enterpriseLicensesConsumed"], 2
      end

      test "renders licensing-enterprise-overview partial if customer is volume" do
        @business.customer.update(metered_plan: false)

        as @owner
        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_select "react-partial[partial-name=licensing-enterprise-overview]"
      end

      test "does not render licensing-enterprise-overview partial if customer is copilot-only" do
        @business.customer.update(metered_plan: true)
        @business.update(seats_plan_type: :basic)

        as @owner
        get "/enterprises/#{business.slug}/enterprise_licensing"

        refute_select "react-partial[partial-name=licensing-enterprise-overview]"
      end

      test "renders licensing-advanced-security-overview partial if flag is enabled" do
        enable_feature_flag(:enterprise_licensing_advanced_security, @owner)

        as @owner
        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_select "react-partial[partial-name=licensing-advanced-security-overview]"
      end

      test "does not render licensing-advanced-security-overview partial if flag is disabled" do
        as @owner
        get "/enterprises/#{business.slug}/enterprise_licensing"

        refute_select "react-partial[partial-name=licensing-advanced-security-overview]"
      end

      test "renders licensing-copilot-overview partial if flag is enabled" do
        enable_feature_flag(:enterprise_copilot_licensing, @owner)

        as @owner
        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_select "react-partial[partial-name=licensing-copilot-overview]"
      end

      test "does not render licensing-copilot-overview partial if flag is disabled" do
        disable_feature_flag(:enterprise_copilot_licensing, @owner)

        as @owner
        get "/enterprises/#{business.slug}/enterprise_licensing"

        refute_select "react-partial[partial-name=licensing-copilot-overview]"
      end

      test "no warning banner shown if within limits" do
        AdvancedSecurityLicense.any_instance.stubs(:seats).returns(50)
        AdvancedSecurityLicense.any_instance.stubs(:consumed_seats).returns(10)
        @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)

        as @owner

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        refute_select " .Banner"
      end

      test "shows a warning if at license limit" do
        AdvancedSecurityLicense.any_instance.stubs(:seats).returns(50)
        AdvancedSecurityLicense.any_instance.stubs(:consumed_seats).returns(50)
        @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)

        as @owner

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_select " .Banner.Banner--warning"
      end

      test "shows an error-style warning if over license limit" do
        AdvancedSecurityLicense.any_instance.stubs(:seats).returns(50)
        AdvancedSecurityLicense.any_instance.stubs(:consumed_seats).returns(70)
        @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)

        as @owner

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_select " .Banner--error"
      end
    else
      test "is not available when billing is disabled" do
        as @owner

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_response :missing
      end
    end
  end

  context "GET /enterprises/:slug/enterprise_licensing/download_active_committers", skip_with_all_emus: true do
    if GitHub.billing_enabled?
      test "is unavailable when advanced security is not enabled" do
        as @owner

        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false) if GitHub.enterprise?

        get "/enterprises/#{@business.slug}/enterprise_licensing/download_active_committers"

        assert_response :missing
      end

      test "is available when billing is enabled" do
        as @owner

        @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)

        VCR.use_cassette("get-committers-for-business", persist_with: :turboghas) do
          get "/enterprises/#{@business.slug}/enterprise_licensing/download_active_committers"
        end

        assert_response :ok
      end
    else
      test "is not available when billing is disabled" do
        as @owner

        get "/enterprises/#{@business.slug}/enterprise_licensing/download_active_committers"

        assert_response :missing
      end
    end
  end

  context "GET /enterprises/:slug/enterprise_licensing/download_consumed_licenses", skip_with_all_emus: true, skip_unless: :billing_enabled? do
    test_business_access do
      get "/enterprises/#{@business.slug}/enterprise_licensing/download_consumed_licenses"
    end

    test "responds with CSV data" do
      email = "test@invite.com"
      @invitation = @organization.invite(email: email, inviter: @organization.admins.first)
      as @owner

      get "/enterprises/#{@business.slug}/enterprise_licensing/download_consumed_licenses"

      assert_response :ok
      assert_match(/attachment;/, response.headers["Content-Disposition"])
      assert_match(/filename="consumed_licenses.csv"/, response.headers["Content-Disposition"])
      assert_includes response.body, @member.login
    end
  end

  context "feedback component" do
    if GitHub.billing_enabled?
      test "sets KV store for user on dismissal" do
        survey_id = "test-survey"
        target_setting_key = Licensing::FeedbackLinkComponent.dismissal_setting_key(survey_id: survey_id, business_slug: @business.slug)
        refute Billing::Kv.store.exists(target_setting_key).value!

        as @owner
        delete "/enterprises/#{@business.to_param}/enterprise_licensing/settings/survey", params: { id: survey_id }

        assert_response :redirect
        assert Billing::Kv.store.exists(target_setting_key).value!
      end

      test "does not render when banner is dismissed" do
        enable_feature_flag(:enterprise_licensing_feedback_survey, @business)

        survey_id = "enterprise-licensing-admins-feedback-survey"
        target_setting_key = Licensing::FeedbackLinkComponent.dismissal_setting_key(survey_id: survey_id, business_slug: @business.slug)

        as @owner
        get "/enterprises/#{@business.to_param}/enterprise_licensing"
        assert_test_selector("enterprise-licensing-admins-feedback-survey", count: 1)

        as @user
        delete "/settings/survey#destroy", params: { id: survey_id }

        as @user
        get "/enterprises/#{@business.to_param}/enterprise_licensing"
        refute_test_selector "enterprise-licensing-admins-feedback-survey"
      end

      test "renders when feature flag is enabled" do
        enable_feature_flag(:enterprise_licensing_feedback_survey, @business)

        as @owner
        get "/enterprises/#{@business.to_param}/enterprise_licensing"

        assert_test_selector("enterprise-licensing-admins-feedback-survey", count: 1)
      end

      test "does not render when feature flag is disabled" do
        disable_feature_flag(:enterprise_licensing_feedback_survey, @business)

        as @owner
        get "/enterprises/#{@business.to_param}/enterprise_licensing"

        refute_test_selector "enterprise-licensing-admins-feedback-survey"
      end
    end
  end
end

class BusinessesEnterpriseLicensingControllerStandaloneHttpTest < GitHub::IntegrationTestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include HydroTestHelpers
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @business = create(:business, :with_azure_subscription, seats_plan_type: :basic)
    @team = create(:copilot_enterprise_team, supplied_business: @business)
    @owner = @business.owners.first
    provider = create(:business_saml_provider, business: @business)
    create(:external_identity, provider: provider, user: @owner)
  end

  setup do
    enable_feature_flag(:strict_zuora_validation_on_metered_billable_check)
  end

  context "Copilot enterprise team license view" do
    test "renders UI" do
      as @owner, external_identities: @owner.external_identities.first

      get "/enterprises/#{@team.business.slug}/enterprise_licensing"

      refute_match "Copilot licenses", response.body
      assert_match "Copilot Business", response.body
    end

    context "when Copilot is disabled" do
      test "show enablement link view when there are no seat assignments" do
        as @owner, external_identities: @owner.external_identities.first

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        refute_test_selector "copilot-standalone-manage-seats-link"
        assert_select "h2", { text: "Copilot Business is disabled" }
        assert_select "p", { text: "You need to enable Copilot Business first before assigning seats." }
        assert_select "a[href='#{settings_copilot_enterprise_path(@business)}']", { text: "Go to policies" }
      end

      test "does not show link when enterprise is unbillable" do
        Copilot::Business.any_instance.stubs(:copilot_billable?).returns(false)
        as @owner, external_identities: @owner.external_identities.first

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_includes response.body, "You must have a valid payment method to use Copilot."
        assert_includes response.body, "Copilot Business is disabled"
        refute_select "a[href='#{settings_copilot_enterprise_path(@business)}']", text: "Manage policies"
      end

      test "shows the correct banner when business does not have an azure sub id" do
        as @owner, external_identities: @owner.external_identities.first

        @business.customer.update(azure_subscription_id: nil)

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_match /You must have a valid payment method to use Copilot./, response.body
        assert_match /Add an Azure subscription/, response.body
        assert_select "a[href='#{settings_billing_tab_enterprise_path(@business, :payment_information)}']"
      end

      test "shows the correct banner when business is not metered" do
        as @owner, external_identities: @owner.external_identities.first

        @business.enterprise_agreements.destroy_all

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_match /You must have a valid payment method to use Copilot./, response.body
        assert_match /Contact your sales rep to enable metered billing for your account./, response.body
      end

      test "shows catchall non-billable banner otherwise" do
        Copilot::Business.any_instance.stubs(:copilot_billable?).returns(false)
        as @owner, external_identities: @owner.external_identities.first

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_match /You must have a valid payment method to use Copilot./, response.body
        assert_match /Contact your sales rep for help enabling Copilot./, response.body
      end

      test "show breakdown and alert banner when there are seat assignments" do
        assignment = create(:copilot_seat_assignment, :enterprise_team, supplied_enterprise_team: @team)
        assignment.convert_to_seats

        as @owner, external_identities: @owner.external_identities.first

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        refute_includes response.body, "Add an Azure subscription"

        assert_select "span", { text: "Total consumed seats" }
        assert_test_selector "copilot-team-seat-cost", { text: "$38.00" }
        assert_select "span", { text: "Copilot is disabled." }
        assert_select "a" do |links|
          links.any? { |link| link[:text] == "Go to policies to enable Copilot." && link[:href] == settings_copilot_enterprise_path(@business) }
        end
      end
    end

    context "when Copilot is enabled" do
      test "displays Manage seats link" do
        Copilot::Business.new(@business).enable_copilot!
        as @owner, external_identities: @owner.external_identities.first

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_test_selector "copilot-standalone-manage-seats-link"
        assert_select "a[href='#{team_seats_enterprise_path(@business)}']"
      end

      test "shows seats breakdown" do
        assignment = create(:copilot_seat_assignment, :enterprise_team, supplied_enterprise_team: @team)
        assignment.convert_to_seats

        Copilot::Business.new(@business).enable_copilot!

        as @owner, external_identities: @owner.external_identities.first

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        refute_includes response.body, "Add an Azure subscription"

        assert_select "span", { text: "Total consumed seats" }
        assert_test_selector "copilot-team-seat-count", { text: "2" }
        assert_includes response.body, "Number of unique members with access to Copilot Business."

        assert_test_selector "copilot-team-seat-cost", { text: "$38.00" }
        assert_includes response.body, "Estimated monthly cost"
        assert_includes response.body, "Each seat is $19/month."
      end

      test "when azure sub id is missing" do
        Copilot::Business.new(@business).enable_copilot!
        as @owner, external_identities: @owner.external_identities.first

        @business.customer.update(azure_subscription_id: nil)

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        refute_test_selector "copilot-standalone-manage-seats-link"

        assert_match /You must have a valid payment method to use Copilot./, response.body
        assert_match /Add an Azure subscription/, response.body
        assert_select "a[href='#{settings_billing_tab_enterprise_path(@business, :payment_information)}']"
      end

      test "when business is not metered" do
        Copilot::Business.new(@business).enable_copilot!
        as @owner, external_identities: @owner.external_identities.first

        @business.enterprise_agreements.destroy_all

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        refute_test_selector "copilot-standalone-manage-seats-link"

        assert_match /You must have a valid payment method to use Copilot./, response.body
        assert_match /Contact your sales rep to enable metered billing for your account./, response.body
        refute_select "a[href='#{settings_billing_tab_enterprise_path(@business, :payment_information)}']"
      end

      test "when otherwise non-billable" do
        Copilot::Business.new(@business).enable_copilot!
        Copilot::Business.any_instance.stubs(:copilot_billable?).returns(false)
        as @owner, external_identities: @owner.external_identities.first

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        refute_test_selector "copilot-standalone-manage-seats-link"

        assert_match /You must have a valid payment method to use Copilot./, response.body
        assert_match /Contact your sales rep for help enabling Copilot./, response.body
        refute_select "a[href='#{settings_billing_tab_enterprise_path(@business, :payment_information)}']"
      end
    end
  end
end if TestEnv.test_with_all_emus? && !GitHub.enterprise? && !TestEnv.test_in_multitenancy_mode?
