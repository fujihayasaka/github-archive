# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationOnboarding::TrialBannerControllerTest < GitHub::IntegrationTestCase

  fixtures do
    @billing_plan_subscription = create(:billing_plan_subscription, :business_owned)
    @org_admin = create :user
    @org_admin_with_global_notice = create :user
    @org_member = create :user
    @rando = create :user
    @organization = create :organization, admins: [@org_admin, @org_admin_with_global_notice]

    @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
  end

  setup do
    @business = @billing_plan_subscription.business
    @owner = @business.owners.first
    @org_admin_with_global_notice.global_notice.set(:billing_email)

    @organization.add_member(@org_member)
    @business.add_organization(@organization)
    @advanced_security_product = ::AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT
  end

  context "GET #show" do
    test "renders an advanced security trial banner component", skip_enterprise: true, skip_with_all_emus: true do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: ::Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?

        as @org_admin
        get "/orgs/#{@organization.display_login}/organization_onboarding/trial_banner", xhr: true
        assert_response_success
        assert_test_selector "advanced-security-trial-banner"
      end
    end

    test "does not render when trial is not active", skip_enterprise: true, skip_with_all_emus: true do
      as @org_admin
      get "/orgs/#{@organization.display_login}/organization_onboarding/trial_banner", xhr: true
      assert_response_success
      refute_test_selector "advanced-security-trial-banner"
    end

    test "does not render when global notice is active", skip_enterprise: true, skip_with_all_emus: true do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: ::Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?

        as @org_admin_with_global_notice
        get "/orgs/#{@organization.display_login}/organization_onboarding/trial_banner", xhr: true
        assert_response_success
        refute_test_selector "advanced-security-trial-banner"
      end
    end

    test "does not render for org member or person outside of org", skip_enterprise: true, skip_with_all_emus: true do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: ::Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?

        as @org_member
        get "/orgs/#{@organization.display_login}/organization_onboarding/trial_banner", xhr: true
        assert_response_success
        refute_test_selector "advanced-security-trial-banner"

        as @rando
        get "/orgs/#{@organization.display_login}/organization_onboarding/trial_banner", xhr: true
        assert_response_success
        refute_test_selector "advanced-security-trial-banner"
      end
    end

    test "does not render for logged out user", skip_enterprise: true, skip_with_all_emus: true do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: ::Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?

        get "/orgs/#{@organization.display_login}/organization_onboarding/trial_banner", xhr: true
        assert_response_success
        refute_test_selector "advanced-security-trial-banner"
      end
    end

    test "does not render if billing is disabled", skip_enterprise: true, skip_with_all_emus: true do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: ::Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?

        GitHub.stubs(:billing_enabled?).returns(false)
        as @org_admin
        get "/orgs/#{@organization.display_login}/organization_onboarding/trial_banner", xhr: true
        assert_response_success
        refute_test_selector "advanced-security-trial-banner"
      end
    end

    test "does not render if unknown org", skip_enterprise: true, skip_with_all_emus: true do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: ::Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?

        GitHub.stubs(:billing_enabled?).returns(false)
        as @org_admin
        get "/orgs/notanorg/organization_onboarding/trial_banner", xhr: true
        assert_response_success
        refute_test_selector "advanced-security-trial-banner"
      end
    end

    test "ignores requests when not xhr", skip_enterprise: true, skip_with_all_emus: true do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: ::Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?

        as @org_admin
        get "/orgs/#{@organization.display_login}/organization_onboarding/trial_banner"
        assert_response :not_acceptable
      end
    end

    if TestEnv.test_with_all_emus?
      test "does not render for EMU", skip_enterprise: true do
        as @org_admin
        get "/orgs/#{@organization.display_login}/organization_onboarding/trial_banner", xhr: true
        assert_response_success
        refute_test_selector "advanced-security-trial-banner"
      end
    end
  end
end
