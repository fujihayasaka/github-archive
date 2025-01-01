# typed: true
# frozen_string_literal: true

require "test_helper"

class RolesAndPermissionsDependencyTest < GitHub::TestCase
  fixtures do
    @business = create(:business)
  end

  setup do
    disable_feature_flag(:erp_staffship)
    disable_feature_flag(:erp_preview)

    disable_feature_flag(:my_feature)
    disable_feature_flag(:erp_staffship_my_feature)
    disable_feature_flag(:erp_preview_my_feature)

    enable_feature_flag(:enterprise_custom_organization_roles)
    enable_feature_flag(:custom_enterprise_role_feature)
  end

  context "#erp_feature_enabled?" do
    test "returns true when feature is enabled" do
      enable_feature_flag(:my_feature, @business)

      assert @business.erp_feature_enabled?(:my_feature)
    end

    test "returns false when feature is enabled for staffship but erp_staffship is disabled" do
      enable_feature_flag(:erp_staffship_my_feature)

      refute @business.erp_feature_enabled?(:my_feature)
    end

    test "returns false when feature is disabled for staffship but erp_staffship is enabled" do
      enable_feature_flag(:erp_staffship)

      refute @business.erp_feature_enabled?(:my_feature)
    end

    test "returns true when feature is enabled for staffship and erp_staffship is enabled" do
      enable_feature_flag(:erp_staffship)
      enable_feature_flag(:erp_staffship_my_feature)

      assert @business.erp_feature_enabled?(:my_feature)
    end

    test "returns false when feature is enabled for preview but erp_preview is disabled" do
      enable_feature_flag(:erp_preview_my_feature)

      refute @business.erp_feature_enabled?(:my_feature)
    end

    test "returns false when feature is disabled for preview but erp_preview is enabled" do
      enable_feature_flag(:erp_preview)

      refute @business.erp_feature_enabled?(:my_feature)
    end

    test "returns true when feature is enabled for preview and erp_preview is enabled" do
      enable_feature_flag(:erp_preview)
      enable_feature_flag(:erp_preview_my_feature)

      assert @business.erp_feature_enabled?(:my_feature)
    end
  end

  context "#custom_enterprise_roles_supported?" do
    test "returns true when plan supports custom roles and enterprise custom roles feature is enabled" do
      assert @business.custom_enterprise_roles_supported?
    end

    test "returns false when plan does not support custom roles", skip_enterprise: true do
      @business.downgrade_to_free_plan

      refute @business.custom_enterprise_roles_supported?
    end

    test "returns false when enterprise custom roles feature is disabled" do
      disable_feature_flag(:custom_enterprise_role_feature)

      refute @business.custom_enterprise_roles_supported?
    end
  end

  context "#custom_organization_roles_supported?" do
    test "returns true when plan supports custom roles and enterprise custom roles feature is enabled" do
      assert @business.custom_organization_roles_supported?
    end

    test "returns false when plan does not support custom roles", skip_enterprise: true do
      @business.downgrade_to_free_plan

      refute @business.custom_organization_roles_supported?
    end

    test "returns false when enterprise custom roles feature is disabled" do
      disable_feature_flag(:enterprise_custom_organization_roles)

      refute @business.custom_organization_roles_supported?
    end
  end

  context "#enterprise_teams_org_roles_supported?" do
    test "returns true enterprise teams org roles feature is enabled" do
      enable_feature_flag(:enterprise_teams_org_roles, @business)
      assert @business.enterprise_teams_org_roles_supported?
    end

    test "returns false when enterprise custom roles feature is disabled" do
      disable_feature_flag(:enterprise_teams_org_roles, @business)

      refute @business.enterprise_teams_org_roles_supported?
    end
  end
end
