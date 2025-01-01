# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class BusinessActorPermissionsOrganizationsTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    if GitHub.single_business_environment?
      GitHub::Enterprise.ensure_business!
      @business = GitHub.global_business
      @business.add_owner(create(:user), actor: nil)
    else
      @business = create(:business)
    end

    @owner = @business.owners.first
    @billing_manager = create :user, login: "billing-manager"
    @business.billing.add_manager(@billing_manager, actor: @owner)
    @member = create :user, login: "member"
    @business.add_user_accounts([@member.id])

    unless GitHub.single_business_environment?
      @enterprise_managed_business = \
        create :business, business_type: :enterprise_managed, shortcode: "qqq"
      @emu_owner = @enterprise_managed_business.owners.first
    end
  end

  setup do
    enable_feature_flag(:custom_enterprise_role_feature, @business)
  end

  context "#actor_can_transfer_organizations?" do
    if GitHub.single_business_environment?
      test "returns false in single business environment" do
        refute @business.actor_can_transfer_organizations?(@owner)
      end
    else
      test "returns false for an externally managed business" do
        assert_predicate @enterprise_managed_business, :enterprise_managed_user_enabled?
        refute @enterprise_managed_business.actor_can_transfer_organizations?(@emu_owner)
      end

      test "returns false for a spammy business" do
        @business.mark_as_spammy
        assert_predicate @business, :spammy?
        refute @business.actor_can_transfer_organizations?(@owner)
      end

      test "returns false for a trial business" do
        @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
        assert_predicate @business, :trial?
        refute @business.actor_can_transfer_organizations?(@owner)
      end

      test "returns false if actor is blank" do
        refute @business.actor_can_transfer_organizations?(nil)
      end

      test "returns false for billing manager of eligible business" do
        refute @business.actor_can_transfer_organizations?(@billing_manager)
      end

      test "returns true for owner of eligible business" do
        assert @business.actor_can_transfer_organizations?(@owner)
      end
    end
  end

  context "#actor_can_remove_organizations?" do
    if GitHub.single_business_environment?
      test "returns false in single business environment" do
        refute @business.actor_can_remove_organizations?(@owner)
      end
    else
      test "returns false for an externally managed business" do
        refute @enterprise_managed_business.actor_can_remove_organizations?(@emu_owner)
      end

      test "returns false when actor is nil" do
        refute @business.actor_can_remove_organizations?(nil)
      end

      test "returns true for business owners" do
        assert @business.actor_can_remove_organizations?(@owner)
      end

      test "returns false when actor does not have permission" do
        refute @business.actor_can_remove_organizations?(@member)
      end

      test "returns true when actor has permission" do
        enable_feature_flag(:enterprise_fgps_org_administration, @business)
        grant_custom_enterprise_role(user: @member, target: @business, fgps: [:remove_enterprise_organizations])
        assert @business.actor_can_remove_organizations?(@member)
      end

      test "returns false when actor has permission but feature flag is off" do
        enable_feature_flag(:enterprise_fgps_org_administration, @business)
        grant_custom_enterprise_role(user: @member, target: @business, fgps: [:remove_enterprise_organizations])
        assert @business.actor_can_remove_organizations?(@member)

        disable_feature_flag(:enterprise_fgps_org_administration, @business)
        refute @business.actor_can_remove_organizations?(@member)
      end

      test "returns true for owner when feature flags are off" do
        disable_feature_flag(:enterprise_fgps_org_administration, @business)
        assert @business.actor_can_remove_organizations?(@owner)
      end
    end
  end
end
