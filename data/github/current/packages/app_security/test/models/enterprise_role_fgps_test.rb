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

      assert_same_elements [@custom_ent_fgp.action.to_sym], fgps.available_fgps(@business).map(&:label)
      refute_includes fgps.available_fgps(@business).map(&:label), @ent_fgp.action.to_sym
    end
  end
end
