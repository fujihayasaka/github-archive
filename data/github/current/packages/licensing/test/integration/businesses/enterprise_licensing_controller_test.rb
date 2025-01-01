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
    @export = Business::LicenseConsumptionExport.create(business: @business, actor: @owner)
    create(:billing_product_uuid, :advanced_security)
  end

  setup do
    @s3_client = Aws::S3::Client.new(stub_responses: true)
    GitHub.stubs(:s3_license_consumption_client).returns(@s3_client)

    GitHub.flipper[:licensing_overview_ghe_volume].disable(@owner)
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

      test "includes link to enterprise people page for owners" do
        as @owner
        get "/enterprises/#{@business}/enterprise_licensing"
        assert_response :success
        assert_select "[data-test-selector='view-details-people-link']"
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

      test "renders metered license overview for metered customers" do
        @business.customer.update(metered_plan: true)

        as @owner
        get "/enterprises/#{@business.slug}/enterprise_licensing"

        refute_select "[data-test-selector='license-overview-totals']"
        refute_select "[data-test-selector='license-overview-available']"
      end

      test "renders standard license overview for non-metered customers" do
        as @owner
        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_select "[data-test-selector='license-overview-totals']"
        assert_select "[data-test-selector='license-overview-available']"
      end

      test "does not blow up for businesses with advanced security enabled" do
        @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
        @business.set_advanced_security_seats_for_entity(seats: 42, actor: @owner)

        as @owner

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
        refute_test_selector "advanced-security-license-promo"
        refute_test_selector "advanced-security-license-self-serve"

        @business.customer.azure_subscription_id = "12345"
        @business.mark_advanced_security_as_metered_for_entity(actor: @owner)

        as @owner

        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "advanced-security-license-sales-serve"
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
        refute_test_selector "advanced-security-license-promo"
        refute_test_selector "advanced-security-license-self-serve"
      end

      test "advertises advanced security if a customer is eligible for it" do
        business = create :business, :with_self_serve_payment, owners: [@owner]

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success
        refute_test_selector "advanced-security-license-sales-serve"
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
          refute_test_selector "advanced-security-license-promo"
          refute_test_selector "advanced-security-license-self-serve"
        end
      end

      test "can manage advanced security seats if a customer is eligible for it" do
        business = create :business, :with_self_serve_payment, owners: [@owner]
        business.subscribe_to_advanced_security(seats: 42, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

        as @owner

        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_response :success

        refute_test_selector "advanced-security-license-sales-serve"
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
        refute_test_selector "advanced-security-license-promo"
        refute_test_selector "advanced-security-license-self-serve"
      end

      test "shows background job form" do
        as @owner
        get "/enterprises/#{@business.slug}/enterprise_licensing"
        assert_select "form[class='js-license-usage-download-form']"
      end

      test "renders the manage seats tab for owners" do
        @business.customer.update(billing_type: ::Customer::BILLING_TYPE_CARD)

        as @owner
        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_response :success
        assert_test_selector "business-manage-seats"
      end

      test "does not render the manage seats tab if enterprise is in dunning" do
        @business.customer.update(billing_type: ::Customer::BILLING_TYPE_CARD)
        create :manual_dunning_period, :with_business, customer: @business.customer
        @business.increment_billing_attempts
        @business.save!

        as @owner
        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_response :success
        refute_test_selector "business-manage-seats"
      end

      test "does not render the manage seats tab if the enterprise has been downgraded to the free plan" do
        @business.customer.update(billing_type: ::Customer::BILLING_TYPE_CARD)
        @business.downgrade_to_free_plan

        as @owner
        get "/enterprises/#{@business.slug}/enterprise_licensing"

        assert_response :success
        refute_test_selector "business-manage-seats"
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

        as @owner
        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_select "react-partial[partial-name=licensing-enterprise-overview]"

        embedded_data = get_react_partial_embedded_json("licensing-enterprise-overview")

        assert_equal embedded_data["props"]["slug"], business.slug
        assert_equal embedded_data["props"]["ghe"]["enterpriseLicensesConsumed"], 2
      end

      test "renders licensing-enterprise-overview partial for volume if flagged on" do
        GitHub.flipper[:licensing_overview_ghe_volume].enable(@owner)

        @business.customer.update(metered_plan: false)

        as @owner
        get "/enterprises/#{business.slug}/enterprise_licensing"

        assert_select "react-partial[partial-name=licensing-enterprise-overview]"

        embedded_data = get_react_partial_embedded_json("licensing-enterprise-overview")

        assert_equal embedded_data["props"]["slug"], business.slug
        assert_equal embedded_data["props"]["ghe"]["enterpriseLicensesConsumed"], 2
      end

      test "does not render licensing-enterprise-overview partial if customer is not metered" do
        @business.customer.update(metered_plan: false)

        as @owner
        get "/enterprises/#{business.slug}/enterprise_licensing"

        refute_select "react-partial[partial-name=licensing-enterprise-overview]"
      end

      test "does not render licensing-enterprise-overview partial if customer is copilot-only" do
        @business.customer.update(metered_plan: true)
        @business.update(seats_plan_type: :basic)

        as @owner
        get "/enterprises/#{business.slug}/enterprise_licensing"

        refute_select "react-partial[partial-name=licensing-enterprise-overview]"
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

  context "POST /enterprises/:slug/enterprise_licensing/create_export", skip_with_all_emus: true, skip_unless: :billing_enabled? do
    test "works for business owner" do
      as @owner
      assert_difference "Business::LicenseConsumptionExport.count" do
        post "/enterprises/#{@business.to_param}/enterprise_licensing/export"
      end

      body = GitHub::JSON.parse(@response.body)
      @export = @business.license_consumption_exports.last
      expected_body = {
        "export_url" => export_enterprise_licensing_url(token: @export.token, format: @export.format),
        "notify_when_complete" => false,
        "job_url" => job_status_url(@export.token)
      }
      assert_equal expected_body, body
      assert_response :created
    end

    test "responds with notify_when_complete for large businesses" do
      as @owner
      Business::LicenseConsumptionExport.stub_const(:LICENSE_CONSUMPTION_REPORT_EMAIL_USER_COUNT, 1) do
        post "/enterprises/#{@business.to_param}/enterprise_licensing/export"
      end

      body = GitHub::JSON.parse(@response.body)
      @export = @business.license_consumption_exports.last
      expected_body = {
        "export_url" => export_enterprise_licensing_url(token: @export.token, format: @export.format),
        "notify_when_complete" => true,
        "job_url" => job_status_url(@export.token),
        "notify" => "The CSV report is being generated. You'll receive an email at #{@owner.email} as soon as it's ready."
      }
      assert_equal expected_body, body
      assert_response :created
    end

    test "works for business billing manager" do
      as @billing_manager
      assert_difference "Business::LicenseConsumptionExport.count" do
        post "/enterprises/#{@business.to_param}/enterprise_licensing/export"
      end

      body = GitHub::JSON.parse(@response.body)
      @export = @business.license_consumption_exports.last
      expected_body = {
        "export_url" => export_enterprise_licensing_url(token: @export.token, format: @export.format),
        "notify_when_complete" => false,
        "job_url" => job_status_url(@export.token)
      }
      assert_equal expected_body, body
      assert_response :created
    end
  end

  context "GET /enterprises/:slug/enterprise_licensing/export", skip_with_all_emus: true, skip_unless: :billing_enabled?  do
    test "redirects owner to download when token is found" do
      object_attrs = { content_length: 1234 }
      @s3_client.stub_responses(:get_object, object_attrs)
      @s3_client.stub_responses(:head_object, object_attrs)

      as @owner
      get "/enterprises/#{@business.to_param}/enterprise_licensing/export.csv", params: { token: @export.to_param }
      assert_response :success
    end

    test "redirects billing manager to download when token is found" do
      object_attrs = { content_length: 1234 }
      @s3_client.stub_responses(:get_object, object_attrs)
      @s3_client.stub_responses(:head_object, object_attrs)

      as @billing_manager
      get "/enterprises/#{@business.to_param}/enterprise_licensing/export.csv", params: { token: @export.to_param }
      assert_response :success
    end

    test "sets correct response headers for csv export" do
      object_attrs = { content_length: 4234 }
      @s3_client.stub_responses(:get_object, object_attrs)
      @s3_client.stub_responses(:head_object, object_attrs)

      as @owner
      get "/enterprises/#{@business.to_param}/enterprise_licensing/export.csv", params: { token: @export.to_param }
      assert_equal "text/csv", @response.headers["Content-Type"]
      assert_equal "4234", @response.headers["Content-Length"]
      assert_equal "attachment; filename=\"#{@export.human_filename}\"", @response.headers["Content-Disposition"]
    end

    test "renders 404 when attempting to download export where object doesn't exist" do
      @s3_client.stub_responses(:head_object, { status_code: 404, headers: {}, body: "" })

      as @owner
      get "/enterprises/#{@business.to_param}/enterprise_licensing/export.csv", params: { token: @export.to_param }
      assert_response_not_found
    end

    test "renders 404 for regular members" do
      as @member
      get "/enterprises/#{@business.to_param}/enterprise_licensing/export.csv", params: { token: @export.to_param }
      assert_response_not_found
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
    GitHub.flipper[:strict_zuora_validation_on_metered_billable_check].enable
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
        refute_select "a[href='#{settings_copilot_enterprise_path(@business)}']"
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
