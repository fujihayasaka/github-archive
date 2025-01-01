# typed: false
# frozen_string_literal: true

require "test_helper"

class Configurable::ActionsLargerRunnersOnboardingTest < GitHub::TestCase
  include ResiliencyHelpers

  fixtures do
    @user = create(:user)
  end

  setup do
    disable_feature_flag(:larger_runners_skip_eligible_to_use_validation)
    TrustTiers::Tier.expects(:for_billable_owner).never
  end

  context "is_larger_runners_onboarded?", skip_enterprise: true do
    test "returns false if entity is not onboarded" do
      org = create(:organization)
      refute org.is_larger_runners_onboarded?

      business = create(:business)
      refute business.is_larger_runners_onboarded?
    end

    test "returns true if entity is onboarded" do
      org = create(:organization)
      org.onboard_larger_runners(actor: @user)
      assert org.is_larger_runners_onboarded?

      business = create(:business)
      business.onboard_larger_runners(actor: @user)
      assert business.is_larger_runners_onboarded?
    end

    test "onboards organization and business independently" do
      business1 = create(:business)
      org1 = create(:organization, business: business1)
      business1.onboard_larger_runners(actor: @user)
      assert business1.is_larger_runners_onboarded?
      refute org1.is_larger_runners_onboarded?
      # Retrieve entities from DB to make sure that they are not cached
      assert Business.find_by_slug(business1.slug).is_larger_runners_onboarded?
      refute Organization.find_by_login(org1.login).is_larger_runners_onboarded?

      business2 = create(:business)
      org2 = create(:organization, business: business2)
      org2.onboard_larger_runners(actor: @user)
      assert org2.is_larger_runners_onboarded?
      refute business2.is_larger_runners_onboarded?
      # Retrieve entities from DB to make sure that they are not cached
      assert Organization.find_by_login(org2.login).is_larger_runners_onboarded?
      refute Business.find_by_slug(business2.slug).is_larger_runners_onboarded?
    end

    test "fallbacks to false if database cluster is not available" do
      org = create(:organization)
      business = create(:business)

      # Invoke "allow_connections_to" without parameters to restrict all database connections to make sure that fallback logic works as expected
      allow_connections_to do
        refute org.is_larger_runners_onboarded?
        refute business.is_larger_runners_onboarded?
      end
    end
  end

  context "onboard_larger_runners", skip_enterprise: true do
    test "onboards if entity is not onboarded yet" do
      org = create(:organization)
      org.onboard_larger_runners(actor: @user)
      assert org.is_larger_runners_onboarded?

      business = create(:business)
      business.onboard_larger_runners(actor: @user)
      assert business.is_larger_runners_onboarded?

      other_business = create(:business)
      org_under_business = create(:organization, business: other_business)
      org_under_business.onboard_larger_runners(actor: @user)
      assert org_under_business.is_larger_runners_onboarded?
    end

    test "skips if already onboarded" do
      org = create(:organization)
      org.onboard_larger_runners(actor: @user)
      org.onboard_larger_runners(actor: @user)
      assert org.is_larger_runners_onboarded?
    end

    test "ghost can be used to onboard" do
      org = create(:organization)
      org.onboard_larger_runners(actor: User.ghost)
      assert org.is_larger_runners_onboarded?
    end

    test "memoization is updated correctly after onboarding" do
      org = create(:organization)
      refute org.is_larger_runners_onboarded?
      org.onboard_larger_runners(actor: @user)
      assert org.is_larger_runners_onboarded?
    end
  end

  context "can_use_larger_runners?", skip_enterprise: true do
    test "returns true if entity is enabled" do
      org = create(:organization, plan: :business_plus)
      org.onboard_larger_runners(actor: @user)
      assert org.can_use_larger_runners?

      business = create(:business)
      business.onboard_larger_runners(actor: @user)
      assert business.can_use_larger_runners?

      other_business = create(:business)
      org_under_business = create(:organization, business: other_business, plan: :business_plus)
      org_under_business.onboard_larger_runners(actor: @user)
      assert org_under_business.can_use_larger_runners?
    end

    test "returns true if parent entity is onboarded" do
      business = create(:business)
      business.onboard_larger_runners(actor: @user)
      org_under_business = create(:organization, business: business, plan: :business_plus)
      assert org_under_business.can_use_larger_runners?
    end

    test "returns false if entity is onboarded but not eligible to use" do
      org = create(:organization, plan: :free)
      org.onboard_larger_runners(actor: @user)
      refute org.can_use_larger_runners?
    end

    test "returns false if entity and parent are not onboarded" do
      org = create(:organization, plan: :business_plus)
      refute org.can_use_larger_runners?

      business = create(:business)
      refute business.can_use_larger_runners?

      other_business = create(:business)
      org_under_business = create(:organization, business: other_business, plan: :business_plus)
      refute org_under_business.can_use_larger_runners?
    end
  end

  context "larger_runners_onboarded_businesses", skip_enterprise: true do
    test "returns all businesses that have onboarded larger runners" do
      onboarded_bus_1 = create(:business)
      onboarded_bus_1.onboard_larger_runners(actor: @user)
      onboarded_bus_2 = create(:business)
      onboarded_bus_2.onboard_larger_runners(actor: @user)
      offboarded_bus_3 = create(:business)

      onboarded_org = create(:organization, plan: :business_plus)
      onboarded_org.onboard_larger_runners(actor: @user)

      onboarded_org_inside_bus = create(:organization, business: offboarded_bus_3, plan: :business_plus)
      onboarded_org_inside_bus.onboard_larger_runners(actor: @user)

      onboarded_user = create(:user)
      onboarded_user.config.enable("actions_larger_runners_onboarded", @user)

      result = Configurable::ActionsLargerRunnersOnboarding.larger_runners_onboarded_businesses
      assert_same_elements [onboarded_bus_1, onboarded_bus_2], result
    end
  end

  context "larger_runners_onboarded_organizations", skip_enterprise: true do
    test "returns all organizations that have onboarded larger runners" do
      onboarded_org_1 = create(:organization, plan: :business_plus)
      onboarded_org_1.onboard_larger_runners(actor: @user)
      onboarded_org_2 = create(:organization, plan: :business_plus)
      onboarded_org_2.onboard_larger_runners(actor: @user)
      offboarded_org_3 = create(:organization, plan: :business_plus)

      onboarded_bus = create(:business)
      onboarded_bus.onboard_larger_runners(actor: @user)
      onboarded_org_inside_onboarded_bus = create(:organization, business: onboarded_bus, plan: :business_plus)
      onboarded_org_inside_onboarded_bus.onboard_larger_runners(actor: @user)
      offboarded_org_inside_onboarded_bus = create(:organization, business: onboarded_bus, plan: :business_plus)

      offboarded_bus = create(:business)
      onboarded_org_inside_offboarded_bus = create(:organization, business: offboarded_bus, plan: :business_plus)
      onboarded_org_inside_offboarded_bus.onboard_larger_runners(actor: @user)
      offboarded_org_inside_offboarded_bus = create(:organization, business: offboarded_bus, plan: :business_plus)

      onboarded_user = create(:user)
      onboarded_user.config.enable("actions_larger_runners_onboarded", @user)

      result = Configurable::ActionsLargerRunnersOnboarding.larger_runners_onboarded_organizations
      assert_same_elements [onboarded_org_1, onboarded_org_2, onboarded_org_inside_onboarded_bus, onboarded_org_inside_offboarded_bus], result
    end
  end

  context "is_eligible_to_use_larger_runners?", skip_enterprise: true do
    test "returns true if entity is business" do
      business = create(:business)
      assert business.is_eligible_to_use_larger_runners?
    end

    test "returns false if entity is downgraded business (expired trial)" do
      downgraded_bus = create(:business)
      downgraded_bus.downgrade_to_free_plan
      refute downgraded_bus.is_eligible_to_use_larger_runners?
    end

    test "returns false if entity is org inside downgraded business" do
      downgraded_bus = create(:business)
      org1 = create(:organization, plan: :business_plus, business: downgraded_bus)
      org2 = create(:organization, plan: :business_plus, business: downgraded_bus)
      downgraded_bus.downgrade_to_free_plan
      org1.reload
      org2.reload

      refute downgraded_bus.is_eligible_to_use_larger_runners?
      refute org1.is_eligible_to_use_larger_runners?
      refute org2.is_eligible_to_use_larger_runners?
    end

    test "returns true if entity is org with eligible billing plan" do
      org_with_team_billing_plan = create(:organization, plan: :business)
      assert org_with_team_billing_plan.is_eligible_to_use_larger_runners?

      org_with_enterprise_billing_plan = create(:organization, plan: :business_plus)
      assert org_with_enterprise_billing_plan.is_eligible_to_use_larger_runners?
    end

    test "returns false if entity is org with ineligible billing plan" do
      org = create(:organization, plan: :free)
      refute org.is_eligible_to_use_larger_runners?
    end

    test "returns false if entity is spammy" do
      spammy_org = create(:organization, plan: :business_plus, spammy: true)
      refute spammy_org.is_eligible_to_use_larger_runners?
    end

    test "skip validation if feature flag is set" do
      org = create(:organization, plan: :free)
      enable_feature_flag(:larger_runners_skip_eligible_to_use_validation, org)
      assert org.is_eligible_to_use_larger_runners?
    end

    test "returns false if database is not available" do
      business = create(:business)

      # Invoke "allow_connections_to" without parameters to restrict all database connections to make sure that fallback logic works as expected
      allow_connections_to do
        refute business.is_eligible_to_use_larger_runners?
      end
    end
  end

  if GitHub.enterprise?
    context "is_eligible_to_use_larger_runners? for Enterprise" do
      test "returns false if GitHub Enterprise" do
        org_with_team_billing_plan = create(:organization, plan: :business)
        refute org_with_team_billing_plan.is_eligible_to_use_larger_runners?
      end
    end
  end

  context "is_eligible_to_onboard_larger_runners?", skip_enterprise: true do
    test "returns false if org is not eligible to use larger runners" do
      org = create(:organization, plan: :free)
      refute org.is_eligible_to_onboard_larger_runners?
    end

    test "returns false if business is not eligible to use larger runners" do
      bus = create(:business)
      bus.downgrade_to_free_plan
      refute bus.is_eligible_to_onboard_larger_runners?
    end

    test "returns false if org belongs to downgraded business" do
      bus = create(:business)
      org = create(:organization, business: bus, plan: :business_plus)
      bus.downgrade_to_free_plan
      bus.reload
      org.reload
      refute bus.is_eligible_to_onboard_larger_runners?
      refute org.is_eligible_to_onboard_larger_runners?
    end

    test "returns false if business is trial" do
      bus = create(:business, trial_expires_at: 3.days.from_now)
      refute bus.is_eligible_to_onboard_larger_runners?
    end

    test "returns false if org in trial" do
      org = create(:organization, plan: :business_plus)
      trial = Billing::EnterpriseCloudTrial.new(org)
      trial.create
      trial.extend_trial(5.days)
      refute org.is_eligible_to_onboard_larger_runners?
    end

    test "returns false if org belongs to business with trial plan" do
      bus = create(:business, trial_expires_at: 3.days.from_now)
      org = create(:organization, business: bus, plan: :business_plus)
      refute bus.is_eligible_to_onboard_larger_runners?
      refute org.is_eligible_to_onboard_larger_runners?
    end

    test "returns true if org is eligible to onboard since LHRs is GA'd" do
      org = create(:organization, plan: :business_plus)
      assert org.is_eligible_to_onboard_larger_runners?
    end

    test "returns true if business is eligible to onboard since LHRs is GA'd" do
      bus = create(:business)
      assert bus.is_eligible_to_onboard_larger_runners?
    end

    test "skip validation if feature flag is set" do
      org_free = create(:organization, plan: :free)
      enable_feature_flag(:larger_runners_skip_eligible_to_use_validation, org_free)
      assert org_free.is_eligible_to_use_larger_runners?

      org_trial = create(:organization, plan: :business_plus)
      trial = Billing::EnterpriseCloudTrial.new(org_trial)
      trial.create
      trial.extend_trial(5.days)
      enable_feature_flag(:larger_runners_skip_eligible_to_use_validation, org_trial)
      assert org_trial.is_eligible_to_use_larger_runners?

      bus_trial = create(:business, trial_expires_at: 3.days.from_now)
      enable_feature_flag(:larger_runners_skip_eligible_to_use_validation, bus_trial)
      assert bus_trial.is_eligible_to_use_larger_runners?
    end

    test "returns false if database is not available" do
      org = create(:organization, plan: :business_plus)

      # Invoke "allow_connections_to" without parameters to restrict all database connections to make sure that fallback logic works as expected
      allow_connections_to do
        refute org.is_eligible_to_onboard_larger_runners?
      end
    end
  end
end
