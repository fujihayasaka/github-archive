# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationOnboarding::AdvancedSecurityControllerTest < GitHub::IntegrationTestCase

  fixtures do
    @owner = create(:user)
    @member = create(:user)
    @rando = create(:user)

    @business = create(:business, owners: [@owner])
    customer = create(:credit_card_customer)
    @business.update!(customer: customer)
    @business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)
    @child_org = create(:organization, admin: @owner, business: @business, login: "myorg")

    @child_org.add_member(@member)

    @advanced_security_month_product_uuid = create(:billing_product_uuid, :advanced_security)
  end

  if TestEnv.test_in_multitenancy_mode?
    test "returns 404 for multitenant EMU" do

      @business.subscribe_to_advanced_security_trial(
        actor: @owner,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      # If viewed as @owner, this will 200 to a login page in EMU mode.
      as @member

      get "/orgs/myorg/organization_onboarding/advanced_security"
      assert_response_not_found
    end
  else
    context "GET #show" do
      test "show GHAS trial onboarding page when trial is active" do

        @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

        as @owner

        get "/orgs/myorg/organization_onboarding/advanced_security"
        assert_response_success
        assert_match /Advanced Security/, response.body
      end


      test "returns 404 if FF is enabled for standalone org" do
        organization = create(:credit_card_org, plan: "business_plus", admin: @owner)
        GitHub.flipper[:ghas_self_serve_orgs].enable(organization)
        as @owner

        result = organization.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?

        refute organization.show_advanced_security_onboarding?
        get "/orgs/myorg/organization_onboarding/advanced_security"
        assert_response_not_found
      end

      test "returns 404 if not owner" do

        @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

        as @member
        get "/orgs/myorg/organization_onboarding/advanced_security"
        assert_response_not_found

        as @rando
        get "/orgs/myorg/organization_onboarding/advanced_security"
        assert_response_not_found
      end

      test "returns 404 if purchased" do

        @business.subscribe_to_advanced_security(seats: 3, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

        as @owner
        get "/orgs/myorg/organization_onboarding/advanced_security"
        assert_response_not_found
      end

      test "returns 404 if trial then purchased" do
        @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert @business.has_active_advanced_security_trial?

        @business.subscribe_to_advanced_security(seats: 3, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

        as @owner
        get "/orgs/myorg/organization_onboarding/advanced_security"
        assert_response_not_found
      end

      test "returns 200 if trial is recent" do
        jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

        end_date_plus_seven = 0.days
        end_date_plus_eight = 0.days

        travel_to jan_1st do
          free_trial_end_date = GitHub::Billing.today + 30.days
          end_date_plus_seven = free_trial_end_date + 7.days
          end_date_plus_eight = free_trial_end_date + 8.days
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert @business.has_active_advanced_security_trial?
          @business.pending_plan_changes.first.run
          refute @business.has_active_advanced_security_trial?
          as @owner
          get "/orgs/myorg/organization_onboarding/advanced_security"
          assert_response_success
        end
        travel_to end_date_plus_seven do
          as @owner
          get "/orgs/myorg/organization_onboarding/advanced_security"
          assert_response_success
        end
        travel_to end_date_plus_eight do
          as @owner
          get "/orgs/myorg/organization_onboarding/advanced_security"
          assert_response_not_found
        end
      end
    end

    context "survey banner" do

      test "does not display survey banner when trial is active" do

        @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

        as @owner

        get "/orgs/myorg/organization_onboarding/advanced_security"
        assert_response_success
        assert_match /Advanced Security/, response.body
        refute_test_selector "advanced-security-self-serve-trial-survey-banner"
      end
    end

    test "shows survey banner if trial is expired and recent" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

      end_date_plus_seven = 0.days
      end_date_plus_eight = 0.days

      travel_to jan_1st do
        free_trial_end_date = GitHub::Billing.today + 30.days
        end_date_plus_seven = free_trial_end_date + 7.days
        end_date_plus_eight = free_trial_end_date + 8.days
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert @business.has_active_advanced_security_trial?
        @business.pending_plan_changes.first.run
        refute @business.has_active_advanced_security_trial?
        as @owner
        get "/orgs/myorg/organization_onboarding/advanced_security"
        assert_response_success
        assert_test_selector "advanced-security-self-serve-trial-survey-banner"
      end
      travel_to end_date_plus_seven do
        as @owner
        get "/orgs/myorg/organization_onboarding/advanced_security"
        assert_response_success
        assert_test_selector "advanced-security-self-serve-trial-survey-banner"
      end
      travel_to end_date_plus_eight do
        as @owner
        get "/orgs/myorg/organization_onboarding/advanced_security"
        assert_response_not_found
      end
    end

    test "does not show survey banner in other organization views" do
      as @owner
      get "/organizations/myorg/settings/profile"
      assert_response_success
      refute_test_selector "advanced-security-self-serve-trial-survey-banner"
    end
  end
end unless GitHub.enterprise?
