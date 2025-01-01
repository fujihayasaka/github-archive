# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseRoleFgpsTest < GitHub::TestCase
  fixtures do
    @business = create(:business)
  end

  setup do
    # Create FGP for Enterprise Roles
    @ent_fgp = Permissions::FineGrainedPermissionIm.new("do_the_enterprise_thing", target_type: "Business", custom_roles_enabled: false)
    @custom_ent_fgp = Permissions::FineGrainedPermissionIm.new("do_the_custom_role_thing", target_type: "Business", custom_roles_enabled: true)
    disable_feature_flag(:erp_staffship)
    disable_feature_flag(:erp_preview)

    @public_release_fgps = []
    @feature_flagged_fgps = {
      read_enterprise_custom_org_role: :enterprise_custom_organization_roles,
      write_enterprise_custom_org_role: :enterprise_custom_organization_roles,
      read_enterprise_custom_enterprise_role: :custom_enterprise_role_feature,
      write_enterprise_custom_enterprise_role: :custom_enterprise_role_feature,
      remove_enterprise_organizations: :enterprise_fgps_org_administration,
      create_enterprise_organizations: :enterprise_fgps_org_administration,
      read_enterprise_members: :enterprise_fgp_administration,
      read_enterprise_admins: :enterprise_fgp_administration,
      manage_enterprise_members: :enterprise_fgp_administration,
      manage_enterprise_admins: :enterprise_fgp_administration,
      read_enterprise_admins_and_members: :enterprise_fgps_org_administration,
      remove_enterprise_admins_and_members: :enterprise_fgps_org_administration,
    }
    @disabled_feature_flags = @feature_flagged_fgps.values.uniq
  end

  test "EnterpriseRoleFgps.for takes an business" do
    Permissions::FineGrainedPermissionIm.with_testing_permission([@ent_fgp, @custom_ent_fgp]) do
      fgps = EnterpriseRoleFgps.for(business: @business)
      assert fgps
    end
  end

  test "EnterpriseRoleFgps.available_fgps returns available FGPs" do
    Permissions::FineGrainedPermissionIm.with_testing_permission([@ent_fgp, @custom_ent_fgp]) do
      fgps = EnterpriseRoleFgps.for(business: @business)

      expected_fgps = @public_release_fgps.push(@custom_ent_fgp.action.to_sym)
      expected_fgps += @feature_flagged_fgps.keys if TestEnv.test_all_features?

      assert_same_elements expected_fgps, fgps.available_fgps(@business).map(&:label)
      refute_includes fgps.available_fgps(@business).map(&:label), @ent_fgp.action.to_sym
    end
  end

  context "Feature Flagged EnterpriseRoleFgps" do
    test "are not included when FF is disabled" do
      @disabled_feature_flags.each { |ff| disable_feature_flag(ff) }

      # Ensure the feature flags are disabled
      @disabled_feature_flags.each do |ff|
        assert_not @business.feature_enabled?(ff)
      end

      enabled_fgps = EnterpriseRoleFgps.custom_role_fgps(@business)
      @feature_flagged_fgps.keys.each do |fgp|
        refute_includes enabled_fgps, fgp
      end
    end

    test "are included when FF is enabled" do
      @disabled_feature_flags.each { |ff| enable_feature_flag(ff) }
      enabled_fgps = EnterpriseRoleFgps.custom_role_fgps(@business)
      assert_same_elements enabled_fgps, @feature_flagged_fgps.keys
    end
  end
end
