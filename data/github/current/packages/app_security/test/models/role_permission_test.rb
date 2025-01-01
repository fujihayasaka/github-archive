# typed: true
# frozen_string_literal: true

require "test_helper"

class RolePermissionTest < GitHub::TestCase

  context ".custom_roles_enabled" do
    test "returns only custom role enabled FGPs" do
      disabled_fgp = Permissions::FineGrainedPermissionIm.new("custom_role_disabled", target_type: "Repository")
      enabled_fgp = Permissions::FineGrainedPermissionIm.new("custom_role_enabled", target_type: "Repository", custom_roles_enabled: true)
      read = Role.read_role

      Permissions::FineGrainedPermissionIm.with_testing_permission([enabled_fgp, disabled_fgp]) do
        enabled_role_permission = RolePermission.create!(role: read, action: enabled_fgp.action)
        RolePermission.create!(role: read, action: disabled_fgp.action)

        assert_same_elements [enabled_role_permission], RolePermission.where(role: read).custom_roles_enabled
      end
    end
  end


  context "validations" do
    test "role and FGP target types must match for custom-role-enabled FGPs" do
      repo_custom_role = create(:custom_repository_role)
      org_fgp = T.must(Permissions::FineGrainedPermissionIm.where(target_type: "Organization", custom_roles_enabled: true).first)
      mixed_role_permission = RolePermission.new(role: repo_custom_role, action: org_fgp.action)
      refute mixed_role_permission.valid?
    end

    test "role and FGP target types must match for internal-only FGPs" do
      repo_custom_role = create(:custom_repository_role)
      org_fgp = T.must(Permissions::FineGrainedPermissionIm.where(target_type: "Organization", custom_roles_enabled: false).first)
      mixed_role_permission = RolePermission.new(role: repo_custom_role, action: org_fgp.action)
      refute mixed_role_permission.valid?
    end

    test "target type validation is skipped if internal role has no target type" do
      internal_untyped_role = Role.security_manager_role
      internal_untyped_role.update!(target_type: nil) unless internal_untyped_role.target_type.nil?
      org_fgp = T.must(Permissions::FineGrainedPermissionIm.where(target_type: "Organization").first)
      mixed_role_permission = RolePermission.new(role: internal_untyped_role, action: org_fgp.action)
      assert mixed_role_permission.valid?
    end

    test "action must exist" do
      role = create(:custom_repository_role)
      fgp = Permissions::FineGrainedPermissionIm.where(target_type: "Repository", custom_roles_enabled: true).first
      rp = RolePermission.new(role: role, action: "")

      refute rp.valid?
      assert_match /must be present/, rp.errors[:action].first
    end

    test "action must be a known FGP" do
      role = create(:custom_repository_role)
      fgp = Permissions::FineGrainedPermissionIm.where(target_type: "Repository", custom_roles_enabled: true).first
      rp = RolePermission.new(role: role, action: "invalid_action")

      refute rp.valid?
      assert_match /must be valid/, rp.errors[:action].first
    end
  end
end
