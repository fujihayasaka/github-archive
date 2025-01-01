# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class BusinessActorPermissionsMembersTest < GitHub::TestCase
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
    enable_feature_flag(:enterprise_fgp_administration, @business)
  end

  context "#actor_can_read_members?" do
    test "returns false when actor is nil" do
      refute @business.actor_can_read_members?(nil)
    end

    test "returns true for business owners" do
      assert @business.actor_can_read_members?(@owner)
    end

    test "returns false when actor does not have permission" do
      refute @business.actor_can_read_members?(@member)
    end

    test "returns true when actor has read permission" do
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:read_enterprise_members])
      assert @business.actor_can_read_members?(@member)
    end

    test "returns true when actor has legacy read permission" do
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:read_enterprise_admins_and_members])
      assert @business.actor_can_read_members?(@member)
    end

    test "returns true when actor has manage permission" do
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:manage_enterprise_members])
      assert @business.actor_can_read_members?(@member)
    end

    test "does not check for owner when skip_owner_check is used" do
      Business.any_instance.expects(:owner?).never
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:read_enterprise_members])
      assert @business.actor_can_read_members?(@member, skip_owner_check: true)
    end

    test "enterprise_fgp_administration flag stops existing permissions if disabled" do
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:read_enterprise_members])
      assert @business.actor_can_read_members?(@member)

      disable_feature_flag(:enterprise_fgp_administration, @business)
      disable_feature_flag(:erp_staffship, @business)
      disable_feature_flag(:erp_preview, @business)
      disable_feature_flag(:support_enterprise_admins_and_members, @business)
      refute @business.actor_can_read_members?(@member)
    end

    test "enterprise_fgp_administration flag does not stop owner permissions" do
      disable_feature_flag(:enterprise_fgp_administration, @business)
      disable_feature_flag(:erp_staffship, @business)
      disable_feature_flag(:erp_preview, @business)
      disable_feature_flag(:support_enterprise_admins_and_members, @business)
      assert @business.actor_can_read_members?(@owner)
    end
  end

  context "#actor_can_manage_members?" do
    test "returns false when actor is nil" do
      refute @business.actor_can_manage_members?(nil)
    end

    test "returns true for business owners" do
      assert @business.actor_can_manage_members?(@owner)
    end

    test "returns false when actor does not have permission" do
      refute @business.actor_can_manage_members?(@member)
    end

    test "returns false when actor only has read permission" do
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:read_enterprise_members])
      refute @business.actor_can_manage_members?(@member)
    end

    test "returns true when actor has manage permission" do
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:manage_enterprise_members])
      assert @business.actor_can_manage_members?(@member)
    end

    test "does not check for owner when skip_owner_check is used" do
      Business.any_instance.expects(:owner?).never
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:manage_enterprise_members])
      assert @business.actor_can_manage_members?(@member, skip_owner_check: true)
    end

    test "enterprise_fgp_administration flag stops existing permissions if disabled" do
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:manage_enterprise_members])
      assert @business.actor_can_manage_members?(@member)

      disable_feature_flag(:enterprise_fgp_administration, @business)
      disable_feature_flag(:erp_staffship, @business)
      disable_feature_flag(:erp_preview, @business)
      disable_feature_flag(:support_enterprise_admins_and_members, @business)
      refute @business.actor_can_manage_members?(@member)
    end

    test "enterprise_fgp_administration flag does not stop owner permissions" do
      disable_feature_flag(:enterprise_fgp_administration, @business)
      disable_feature_flag(:erp_staffship, @business)
      disable_feature_flag(:erp_preview, @business)
      disable_feature_flag(:support_enterprise_admins_and_members, @business)
      assert @business.actor_can_manage_members?(@owner)
    end
  end

  context "#actor_can_read_admins?" do
    test "returns false when actor is nil" do
      refute @business.actor_can_read_admins?(nil)
    end

    test "returns true for business owners" do
      assert @business.actor_can_read_admins?(@owner)
    end

    test "returns false when actor does not have permission" do
      refute @business.actor_can_read_admins?(@member)
    end

    test "returns true when actor has read admins permission" do
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:read_enterprise_admins])
      assert @business.actor_can_read_admins?(@member)
    end

    test "returns true when actor has manage admins permission" do
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:manage_enterprise_admins])
      assert @business.actor_can_read_admins?(@member)
    end

    test "does not check for owner when skip_owner_check is used" do
      Business.any_instance.expects(:owner?).never
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:read_enterprise_admins])
      assert @business.actor_can_read_admins?(@member, skip_owner_check: true)
    end

    test "enterprise_fgp_administration flag stops existing permissions if disabled" do
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:read_enterprise_admins])
      assert @business.actor_can_read_admins?(@member)

      disable_feature_flag(:enterprise_fgp_administration, @business)
      disable_feature_flag(:erp_staffship, @business)
      disable_feature_flag(:erp_preview, @business)
      disable_feature_flag(:support_enterprise_admins_and_members, @business)
      refute @business.actor_can_read_admins?(@member)
    end

    test "enterprise_fgp_administration flag does not stop owner permissions" do
      disable_feature_flag(:enterprise_fgp_administration, @business)
      disable_feature_flag(:erp_staffship, @business)
      disable_feature_flag(:erp_preview, @business)
      disable_feature_flag(:support_enterprise_admins_and_members, @business)
      assert @business.actor_can_read_admins?(@owner)
    end
  end

  context "#actor_can_manage_admins?" do
    test "returns false when actor is nil" do
      refute @business.actor_can_manage_admins?(nil)
    end

    test "returns true for business owners" do
      assert @business.actor_can_manage_admins?(@owner)
    end

    test "returns false when actor does not have permission" do
      refute @business.actor_can_manage_admins?(@member)
    end

    test "returns false when actor has only read admins permission" do
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:read_enterprise_admins])
      refute @business.actor_can_manage_admins?(@member)
    end

    test "returns true when actor has manage admins permission" do
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:manage_enterprise_admins])
      assert @business.actor_can_manage_admins?(@member)
    end

    test "does not check for owner when skip_owner_check is used" do
      Business.any_instance.expects(:owner?).never
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:manage_enterprise_admins])
      assert @business.actor_can_manage_admins?(@member, skip_owner_check: true)
    end

    test "enterprise_fgp_administration flag stops existing permissions if disabled" do
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:manage_enterprise_admins])
      assert @business.actor_can_manage_admins?(@member)

      disable_feature_flag(:enterprise_fgp_administration, @business)
      disable_feature_flag(:erp_staffship, @business)
      disable_feature_flag(:erp_preview, @business)
      disable_feature_flag(:support_enterprise_admins_and_members, @business)
      refute @business.actor_can_manage_admins?(@member)
    end

    test "enterprise_fgp_administration flag does not stop owner permissions" do
      disable_feature_flag(:enterprise_fgp_administration, @business)
      disable_feature_flag(:erp_staffship, @business)
      disable_feature_flag(:erp_preview, @business)
      disable_feature_flag(:support_enterprise_admins_and_members, @business)
      assert @business.actor_can_manage_admins?(@owner)
    end
  end
end
