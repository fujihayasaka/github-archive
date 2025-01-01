# typed: false
# frozen_string_literal: true

require "test_helper"

class PermissionsSystemRolesTest < GitHub::TestCase
  SYSTEM_ROLE_COUNT = 26
  ROLE_FGP_COUNT    = 236

  setup do
    @system_roles = GitHub.system_roles
    @triage   = Role.triage_role
    @maintain = Role.maintain_role
  end

  context "YAML file parsing and setup" do
    test "the expected number of roles exist" do
      roles = @system_roles.send(:system_roles)
      role_fgps = roles.map { |r| @system_roles.send(:system_permissions_for_role, r) }.flatten
      assert_same_elements Role::SYSTEM_ROLES, roles
      assert_equal ROLE_FGP_COUNT, role_fgps.count
    end
  end

  test "does not change any records in dry_run mode" do
    Role.expects(:save!).never
    Role.expects(:update!).never
    RolePermission.expects(:create!).never
    RolePermission.expects(:destroy_all).never

    @triage.destroy

    role_count = Role.presets.count
    role_fgp_count = RolePermission.count

    @system_roles.reconcile(purge: true, dry_run: true)

    assert_equal role_fgp_count, RolePermission.count
    assert_equal role_count, Role.presets.count
  end

  test "does not blow up in verbose mode" do
    # add/remove a record of each model so that we cover all purge paths
    RolePermission.create!(role_id: Role.triage_role.id, action: "manage_topics")

    role = Role.new(name: "fake_role")
    # we skip validations to be able to create a fake system role
    role.save(validate: false)

    @maintain.destroy!

    @system_roles.reconcile(purge: false, verbose: true, dry_run: true)
    @system_roles.reconcile(purge: true, verbose: true, dry_run: true)
  end

  context "#reconcile" do
    test "rollsback if failure at Role level" do
      @triage.destroy

      role_count = Role.presets.count
      role_fgp_count = RolePermission.count

      Role.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid)
      @system_roles.reconcile(purge: true)

      assert_equal role_fgp_count, RolePermission.count
      assert_equal role_count, Role.presets.count
    end

    test "rollsback if failure at RolePermission level" do
      @triage.destroy

      role_count = Role.presets.count
      role_fgp_count = RolePermission.count

      RolePermission.stubs(:create!).raises(ActiveRecord::RecordInvalid)
      @system_roles.reconcile

      assert_equal role_fgp_count, RolePermission.count
      assert_equal role_count, Role.presets.count
    end

    test "raises error if undefined FGP is used on a role" do
      invalid_config = GitHub.system_roles_config
      invalid_config["system_roles"]["admin"]["permissions"] << "undefined_fgp"
      invalid_system_roles = Permissions::SystemRoles.new(invalid_config)

      assert_raises Permissions::SystemRoles::ReconcileError do
        invalid_system_roles.reconcile
      end
    end
  end

  context "#reconcile_roles" do
    test "new system roles are added" do
      # Remove some system roles so we can test the reconciliation
      Role.write_role.destroy
      Role.triage_role.destroy
      refute_equal SYSTEM_ROLE_COUNT, Role.count

      @system_roles.reconcile

      assert_equal SYSTEM_ROLE_COUNT, Role.presets.count
    end

    test "system roles not present in system roles are not removed when purge is false" do
      role = Role.new(name: "foo")
      # we skip validations to be able to create a fake system role
      role.save(validate: false)

      @system_roles.reconcile

      assert_includes Role.presets.all, role
    end

    test "roles not present in system roles are removed when purge is true" do
      role = Role.new(name: "foo")
      # we skip validations to be able to create a fake system role
      role.save(validate: false)

      refute_equal SYSTEM_ROLE_COUNT, Role.count

      @system_roles.reconcile(purge: true)

      assert_equal SYSTEM_ROLE_COUNT, Role.presets.count
      refute_includes Role.presets.all, role
    end

    test "custom roles are not removed when purge is true" do
      org = create(:business_plus_org)
      custom_role = Role.create!(
        name: "custom", base_role_id: @triage.id,
        owner_id: org.id, owner_type: "Organization")

      assert_equal SYSTEM_ROLE_COUNT + 1, Role.count
      assert_equal SYSTEM_ROLE_COUNT, Role.presets.count

      @system_roles.reconcile(purge: true)

      assert_equal SYSTEM_ROLE_COUNT + 1, Role.count
      assert_equal SYSTEM_ROLE_COUNT, Role.presets.count
      assert_includes Role.all, custom_role
    end
  end

  context "#reconcile_base_roles" do
    test "updates base role for existent roles" do
      read = Role.read_role
      @triage.update(base_role_id: @maintain.id)

      refute_equal read, @triage.base_role

      @system_roles.reconcile
      assert_equal read, @triage.reload.base_role
    end

    test "adds base role for new roles" do
      @maintain.destroy

      @system_roles.reconcile
      assert_equal Role.write_role, Role.maintain_role.base_role
    end
  end

  context "#reconcile_role_target_type" do
    test "does nothing if dry_run is true" do
      @triage.update(target_type: nil)

      @system_roles.reconcile(dry_run: true)
      assert_nil Role.triage_role.target_type
    end

    test "updates target type for existent roles with no target type" do
      @triage.update!(target_type: nil)

      @system_roles.reconcile
      assert_equal "Repository", @triage.reload.target_type
    end

    test "does not set any target type for legacy hybrid roles" do
      @system_roles.reconcile
      internal_system_role = Role.find_by(name: "codespace_org_creator")
      assert_nil internal_system_role.target_type
    end

    test "raises when config target type does not match non-nil database target type" do
      @triage.update!(target_type: "SomeOtherTargetType")

      assert_raises Permissions::SystemRoles::ReconcileError do
        @system_roles.reconcile
      end
      # We can't just reload @triage here since the target_type, and thus the subclass of Role has changed
      assert_equal "SomeOtherTargetType", Role.find(@triage.id).target_type
    end

    test "adds target type for new roles" do
      @maintain.destroy

      @system_roles.reconcile
      assert_equal "Repository", Role.maintain_role.target_type
    end
  end

  context "#reconcile_permissions" do
    test "missing role_permissions are added" do
      # remove some pre-existing role_permissions so we can test the reconciliation
      RolePermission.destroy_by(role_id: @maintain.id, action: "manage_topics")
      refute_equal ROLE_FGP_COUNT, RolePermission.count

      @system_roles.reconcile

      assert_equal ROLE_FGP_COUNT, RolePermission.count
      assert RolePermission.find_by(role_id: @maintain.id, action: "manage_topics")
    end

    test "extra role_permissions are not removed when purge is false" do
      existent_fgp = Permissions::FineGrainedPermissionIm.find(:manage_topics)

      # new role_permission with existent FGP
      role_permission = RolePermission.create(role_id: @triage.id, action: existent_fgp.action)

      @system_roles.reconcile

      assert_includes RolePermission.all, role_permission
    end

    test "extra permissions are removed when purge is true" do
      fake_fgp = Permissions::FineGrainedPermissionIm.new("fake_action", target_type: "Repository")
      Permissions::FineGrainedPermissionIm.with_testing_permission(fake_fgp) do
        # new role_permission with new FGP
        role_permission = RolePermission.create(role_id: @triage.id, action: fake_fgp.action)

        refute_equal ROLE_FGP_COUNT, RolePermission.count

        @system_roles.reconcile(purge: true)

        assert_equal ROLE_FGP_COUNT, RolePermission.count
        refute_includes RolePermission.all, role_permission
      end
    end

    test "extra role_permissions are removed when purge is true" do
      existent_fgp = Permissions::FineGrainedPermissionIm.find(:manage_topics)

      # new role_permission with existent FGP
      role_permission = RolePermission.create(role_id: @triage.id, action: existent_fgp.action)

      refute_equal ROLE_FGP_COUNT, RolePermission.count

      @system_roles.reconcile(purge: true)

      assert_equal ROLE_FGP_COUNT, RolePermission.count

      refute_includes RolePermission.all, role_permission
    end
  end
end
