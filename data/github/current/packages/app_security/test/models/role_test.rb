# typed: true
# frozen_string_literal: true

require "test_helper"

class RoleTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper
  include HydroTestHelpers

  fixtures do
    @read = Role.read_role
    @triage = Role.triage_role
    @write = Role.write_role
    @maintain = Role.maintain_role
    @admin = Role.admin_role
    @package_reader = Role.package_reader_role
    @package_writer = Role.package_writer_role
    @package_admin = Role.package_admin_role

    @org = create(:business_plus_organization, login: "github")
  end

  setup do
    if GitHub.enterprise?
      GitHub::Plan.stubs(:business_plus).raises(StandardError.new("No plan found for business_plus"))
    end
  end

  context "validations" do
    test "does not allow creating roles with reserved names" do
      # Ability.actions.keys are ["read", "write", "admin"]
      reserved_role_names = Ability.actions.keys + %w[triage maintain pull push]
      reserved_role_names.each do |ability_action|
        role = build(:role, name: ability_action.dup, owner_id: @org.id, owner_type: "Organization")
        refute_predicate role, :valid?
        assert_equal "Name is a reserved role name", role.errors.full_messages.to_sentence
      end
    end

    test "does not allow creating roles with reserved names using case-insensitive comparisons" do
      # Ability.actions.keys are ["read", "write", "admin"]
      reserved_role_names = Ability.actions.keys.map(&:upcase) + %w[TriaGe MaiNTain puLL pUSh]
      reserved_role_names.each do |ability_action|
        role = build(:role, name: ability_action.dup, owner_id: @org.id, owner_type: "Organization")
        refute_predicate role, :valid?
        assert_equal "Name is a reserved role name", role.errors.full_messages.to_sentence
      end
    end

    test "requires owner for custom roles" do
      role = build(:role, owner: nil)
      refute_predicate role, :valid?
      assert_equal "Owner can't be blank and Owner does not have the correct plan to create custom roles", role.errors.full_messages.to_sentence
    end

    test "can not create a custom role for free plans" do
      org = create(:organization, plan: "free")
      role = build(:role, owner_id: org.id, owner_type: "Organization", base_role_id: @read.id)

      assert_equal 0, RepositoryRole.custom_roles_for_org(org).count

      refute_predicate role, :valid?
      assert_equal "Owner does not have the correct plan to create custom roles", role.errors.full_messages.to_sentence
    end

    test "must have the correct plan to create custom roles" do
      basic_org = create(:organization, plan: "bronze")
      role = build(:role, owner_id: basic_org.id, owner_type: "Organization")
      refute_predicate role, :valid?
      assert_equal "Owner does not have the correct plan to create custom roles", role.errors.full_messages.to_sentence
    end

    test "cannot create a custom role when owner_type is User" do
      role = RepositoryRole.new(name: "test", owner: @org, base_role_id: @read.id)
      assert_equal "User", role.owner_type
      refute role.valid?
      assert role.errors[:owner_type].include?("is not included in the list")
    end

    test "cannot create a custom role when owner_type is not Organization" do
      role = RepositoryRole.new(name: "test", owner_id: @org.id, owner_type: "Repository", base_role_id: @read.id)
      refute role.valid?
      assert role.errors[:owner_type].include?("is not included in the list")
    end
  end

  context "retrieving custom roles" do
    test ".custom_roles_for_org returns all types of custom roles" do
      other_org = create(:business_plus_organization)
      custom_repo_role = create_custom_role(owner: @org)
      custom_org_role = OrganizationRole.create!(
        name: "role-#{SecureRandom.hex(12)}",
        description: "Role description",
        owner_id: @org.id,
        owner_type: "Organization"
      )

      create_custom_role(owner: other_org)

      roles = Role.custom_roles_for_org(@org)
      assert_equal 2, roles.count
      assert_same_elements [custom_repo_role, custom_org_role], roles
    end

    test ".custom_role_by_name retrieves all types of roles" do
      GitHub.flipper[:custom_enterprise_role_feature].enable
      ent = create(:business)
      org = create(:business_plus_organization)
      custom_ent_role = create(:custom_enterprise_role, owner_id: ent.id, owner_type: "Business")
      custom_org_role = create(:custom_organization_role, owner_id: org.id, owner_type: "Organization")
      custom_repo_role = create_custom_role(owner: org)

      ent_role = Role.custom_role_by_name(custom_ent_role.name, owner: ent)
      org_role = Role.custom_role_by_name(custom_org_role.name, owner: org)
      repo_role = Role.custom_role_by_name(custom_repo_role.name, owner: org)

      assert_equal custom_ent_role, ent_role
      assert_equal custom_org_role, org_role
      assert_equal custom_repo_role, repo_role
    end
  end

  context ".valid_system_role?" do
    test  "true for lowercase system roles" do
      assert Role.valid_system_role?(:read)
      assert Role.valid_system_role?("write")
      assert Role.valid_system_role?("admin")
      assert Role.valid_system_role?("pull")
      assert Role.valid_system_role?(:push)
    end

    test "true for uppercase system roles" do
      assert Role.valid_system_role?(:Read)
      assert Role.valid_system_role?("Write")
      assert Role.valid_system_role?("Admin")
      assert Role.valid_system_role?("Pull")
      assert Role.valid_system_role?(:Push)
    end

    test "false for non system roles" do
      refute Role.valid_system_role?(:foo)
      refute Role.valid_system_role?("bar")
    end
  end

  context ".read_role" do
    test "returns the preset read role" do
      read_role = Role.find_by(name: "read", owner_type: nil, owner_id: nil)
      assert_equal read_role, @read
      assert_predicate @read, :preset?
    end
  end

  context ".triage_role" do
    test "returns the preset tirage role" do
      triage_role = Role.find_by(name: "triage", owner_type: nil, owner_id: nil)
      assert_equal triage_role, @triage
      assert_predicate @triage, :preset?
    end
  end

  context ".write_role" do
    test "returns the preset write role" do
      write_role = Role.find_by(name: "write", owner_type: nil, owner_id: nil)
      assert_equal write_role, @write
      assert_predicate @write, :preset?
    end
  end

  context ".maintain_role" do
    test "returns the preset maintain role" do
      maintain_role = Role.find_by(name: "maintain", owner_type: nil, owner_id: nil)
      assert_equal maintain_role, @maintain
      assert_predicate @maintain, :preset?
    end
  end

  context ".admin_role" do
    test "returns the preset admin role" do
      admin_role = Role.find_by(name: "admin", owner_type: nil, owner_id: nil)
      assert_equal admin_role, @admin
      assert_predicate @admin, :preset?
    end
  end

  context "#less_than_org_default_role?" do
    test "supports preset roles" do
      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:write, actor: @org.owner)
      end
      assert @triage.less_than_org_default_role?(@org)
      refute @write.less_than_org_default_role?(@org)

      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:none, actor: @org.owner)
      end
      refute @triage.less_than_org_default_role?(@org)
      refute @write.less_than_org_default_role?(@org)
    end

    test "supports custom repo roles" do
      read_based = create_custom_role(role_name: "😉 foo", owner: @org, base_role: :read)
      maintain_based = create_custom_role(role_name: "😉 faa", owner: @org, base_role: :maintain)

      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:write, actor: @org.owner)
      end
      assert read_based.less_than_org_default_role?(@org)
      refute maintain_based.less_than_org_default_role?(@org)

      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:none, actor: @org.owner)
      end
      refute read_based.less_than_org_default_role?(@org)
      refute maintain_based.less_than_org_default_role?(@org)
    end

    test "raises for custom org roles" do
      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:write, actor: @org.owner)
      end
      custom_role = create(:custom_organization_role, owner_id: @org.id, owner_type: "Organization")
      assert_raises(NoMethodError) { custom_role.less_than_org_default_role?(@org) }
    end

    test "raises for internal roles without repo target" do
      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:write, actor: @org.owner)
      end
      assert_raises(NoMethodError) { @package_writer.less_than_org_default_role?(@org) }

      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:none, actor: @org.owner)
      end
      assert_raises(NoMethodError) { @package_writer.less_than_org_default_role?(@org) }
    end
  end

  context "#greater_or_equal_to_org_default_role?" do
    test "supports preset roles" do
      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:write, actor: @org.owner)
      end
      refute @triage.greater_or_equal_to_org_default_role?(@org)
      assert @write.greater_or_equal_to_org_default_role?(@org)

      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:none, actor: @org.owner)
      end
      assert @triage.greater_or_equal_to_org_default_role?(@org)
      assert @write.greater_or_equal_to_org_default_role?(@org)
    end

    test "supports custom repo roles" do
      read_based = create_custom_role(role_name: "😉 foo", owner: @org, base_role: :read)
      maintain_based = create_custom_role(role_name: "😉 faa", owner: @org, base_role: :maintain)

      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:write, actor: @org.owner)
      end
      refute read_based.greater_or_equal_to_org_default_role?(@org)
      assert maintain_based.greater_or_equal_to_org_default_role?(@org)

      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:none, actor: @org.owner)
      end
      assert read_based.greater_or_equal_to_org_default_role?(@org)
      assert maintain_based.greater_or_equal_to_org_default_role?(@org)
    end

    test "raises for custom org roles" do
      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:write, actor: @org.owner)
      end
      custom_role = create(:custom_organization_role, owner_id: @org.id, owner_type: "Organization")
      assert_raises(NoMethodError) { custom_role.greater_or_equal_to_org_default_role?(@org) }
    end

    test "raises for internal roles without repo target" do
      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:write, actor: @org.owner)
      end
      assert_raises(NoMethodError) { @package_writer.greater_or_equal_to_org_default_role?(@org) }

      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:none, actor: @org.owner)
      end
      assert_raises(NoMethodError) { @package_admin.greater_or_equal_to_org_default_role?(@org) }
    end
  end

  context "#preset?" do
    test "true for preset roles" do
      assert_predicate @read, :preset?
      assert_predicate @triage, :preset?
      assert_predicate @write, :preset?
      assert_predicate @maintain, :preset?
      assert_predicate @admin, :preset?
      assert_predicate @package_reader, :preset?
      assert_predicate @package_writer, :preset?
      assert_predicate @package_admin, :preset?
    end

    test "false for custom role" do
      refute_predicate build(:role), :preset?
    end
  end

  context "#custom?" do
    test "false for preset roles" do
      refute_predicate @read, :custom?
      refute_predicate @triage, :custom?
      refute_predicate @write, :custom?
      refute_predicate @maintain, :custom?
      refute_predicate @admin, :custom?
      refute_predicate @package_reader, :custom?
      refute_predicate @package_writer, :custom?
      refute_predicate @package_admin, :custom?
    end

    test "true for custom role" do
      assert_predicate build(:role), :custom?
    end
  end

  context "#internal?" do
    test "false for system roles" do
      refute_predicate @read, :internal?
      refute_predicate @triage, :internal?
      refute_predicate @write, :internal?
      refute_predicate @maintain, :internal?
      refute_predicate @admin, :internal?
    end

    test "false for custom role" do
      refute_predicate build(:role), :internal?
    end

    test "true for internal roles" do
      codespace_creator = Role.presets.find_by(name: "codespace_org_creator")

      assert_predicate codespace_creator, :internal?
      assert_predicate @package_reader, :internal?
      assert_predicate @package_writer, :internal?
      assert_predicate @package_admin, :internal?
    end
  end

  context "#display_name" do
    test "capitalizes system role" do
      assert_equal "Read", @read.display_name
      assert_equal "read", @read.name
    end

    test "capitalizes internal role" do
      assert_equal "Package_reader", @package_reader.display_name
      assert_equal "package_reader", @package_reader.name
    end

    test "does not change custom role" do
      custom_role = create_custom_role(owner: @org, role_name: "lower then UPPER case 🟢")
      assert_equal "lower then UPPER case 🟢", custom_role.display_name
      assert_equal custom_role.display_name, custom_role.name
    end
  end

  context "#target_type" do
    test "can create role with target_type" do
      created_role = Role.create!(target_type: "CustomTargetType", name: "target_type_custom_role", owner: @org, base_role: Role.read_role, owner_type: "Organization")
      loaded_role = Role.find(created_role.id)

      assert_equal "CustomTargetType", created_role.target_type
      assert_equal "CustomTargetType", loaded_role.target_type
    end
  end

  context "#custom_role_permissions" do
    test "returns only custom role enabled role permissions" do
      disabled_fgp = T.must(Permissions::FineGrainedPermissionIm.where(target_type: "Repository", custom_roles_enabled: false).first)
      enabled_fgp = T.must(Permissions::FineGrainedPermissionIm.where(target_type: "Repository", custom_roles_enabled: true).first)

      enabled_role_permission = RolePermission.create!(role: Role.read_role, action: enabled_fgp.action)
      RolePermission.create(role: Role.read_role, action: disabled_fgp.action)

      assert_same_elements [enabled_role_permission], @read.custom_role_permissions
    end

    test "returns only custom role disabled role permissions" do
      disabled_fgps = Permissions::FineGrainedPermissionIm.where(target_type: "Repository", custom_roles_enabled: false)
      disabled_fgps.each { |f| assert_equal f.custom_roles_enabled, false }
    end
  end

  context "#base_role_name_or_self" do
    test "supports ability names" do
      assert_equal "write", Role.base_role_name_or_self("write")
    end

    test "supports reserved names" do
      assert_equal "read", Role.base_role_name_or_self("triage")
    end

    test "raises if no role is found when passing an organization" do
      assert_raises(ActiveRecord::RecordNotFound) { Role.base_role_name_or_self("foo", owner: @org) }
    end

    test "supports internal role names" do
      internal_role_name = Role::PACKAGES_SYSTEM_ROLES.first
      assert_equal internal_role_name, Role.base_role_name_or_self(T.must(internal_role_name))
    end

    test "supports custom role names" do
      create_custom_role(role_name: "😉 foo", owner: @org, base_role: :read)
      assert_equal "read", Role.base_role_name_or_self("😉 foo", owner: @org)
    end

    test "returns internal role even if there is a custom role with the same name if no org is passed" do
      internal_role_name = Role::PACKAGES_SYSTEM_ROLES.first
      create_custom_role(role_name: internal_role_name, owner: @org, base_role: :maintain)
      assert_equal internal_role_name, Role.base_role_name_or_self(T.must(internal_role_name))
    end

    test "ignores the org argument if we pass a RESERVED_ROLE" do
      assert_equal "read", Role.base_role_name_or_self("triage", owner: @org)
    end

    test "supports custom roles with internal role names" do
      internal_role_name = Role::PACKAGES_SYSTEM_ROLES.first
      create_custom_role(role_name: internal_role_name, owner: @org, base_role: :maintain)
      assert_equal "maintain", Role.base_role_name_or_self(T.must(internal_role_name), owner: @org)
    end

    test "returns base role for all repo role" do
      all_repo_admin_name = OrganizationRole.all_repo_admin_role.name
      fake_all_repo_admin = create(:custom_all_repo_role, name: all_repo_admin_name, owner_id: @org.id, base_role_id: Role.read_role.id)
      assert_equal "admin", Role.base_role_name_or_self(all_repo_admin_name)
      assert_equal "read", Role.base_role_name_or_self(all_repo_admin_name, owner: @org)
    end
  end

  context "#read?" do
    test "true for read role" do
      assert_predicate @read, :read?
    end

    test "false for other role" do
      refute_predicate @maintain, :read?
    end
  end

  context "#triage?" do
    test "true for triage role" do
      assert_predicate @triage, :triage?
    end

    test "false for other role" do
      refute_predicate @maintain, :triage?
    end
  end

  context "#write?" do
    test "true for write role" do
      assert_predicate @write, :write?
    end

    test "false for other role" do
      refute_predicate @maintain, :write?
    end
  end

  context "#maintain?" do
    test "true for maintain role" do
      assert_predicate @maintain, :maintain?
    end

    test "false for other role" do
      refute_predicate @triage, :maintain?
    end
  end

  context "#admin?" do
    test "true for admin role" do
      assert_predicate @admin, :admin?
    end

    test "false for other role" do
      refute_predicate @maintain, :admin?
    end
  end

  context "#requires_non_legacy_plan?" do
    test "false for packages system roles" do
      refute_predicate @package_reader, :requires_non_legacy_plan?
      refute_predicate @package_writer, :requires_non_legacy_plan?
      refute_predicate @package_admin, :requires_non_legacy_plan?
    end

    test "true for non packages system roles" do
      assert_predicate @triage, :requires_non_legacy_plan?
      assert_predicate @maintain, :requires_non_legacy_plan?
    end
  end

  context "#owner_must_be_organization?" do
    test "false for packages system roles" do
      refute_predicate @package_reader, :owner_must_be_organization?
      refute_predicate @package_writer, :owner_must_be_organization?
      refute_predicate @package_admin, :owner_must_be_organization?
    end

    test "true for non packages system roles" do
      assert_predicate @read, :owner_must_be_organization?
      assert_predicate @triage, :owner_must_be_organization?
      assert_predicate @write, :owner_must_be_organization?
      assert_predicate @maintain, :owner_must_be_organization?
      assert_predicate @admin, :owner_must_be_organization?
    end
  end

  context "#action_rank" do
    test "returns the action rank for a role" do
      assert_equal 0,   @read.action_rank
      assert_equal 0.5, @triage.action_rank
      assert_equal 1,   @write.action_rank
      assert_equal 1.5, @maintain.action_rank
      assert_equal 2, @admin.action_rank
    end

    test "returns the action rank for base_role if the role is a custom role" do
      assert_equal 0,   create(:custom_repository_role, base_role_id: @read.id).action_rank
      assert_equal 0.5, create(:custom_repository_role, base_role_id: @triage.id).action_rank
      assert_equal 1,   create(:custom_repository_role, base_role_id: @write.id).action_rank
      assert_equal 1.5, create(:custom_repository_role, base_role_id: @maintain.id).action_rank
    end
  end

  test "#has_base_role?" do
    refute @read.has_base_role?
    assert @triage.has_base_role?
    refute @write.has_base_role?
    assert @maintain.has_base_role?
  end

  context "#user_ids" do
    test "gives correct ids for current role" do
      repo = create(:repository, :minimal, owner: @org)
      custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id)
      member, collab, collab2 = create(:user), create(:user), create(:user)

      @org.add_member(member, action: :write)
      repo.add_member(member, action: custom_role.name)
      repo.add_member(collab, action: custom_role.name)
      repo.add_member(collab2, action: "triage")

      assert_same_elements [member.id, collab.id], custom_role.user_ids
    end

    test "gives no ids for unassigned role" do
      another_custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id)
      assert_empty another_custom_role.user_ids
    end
  end

  context "#org_member_ids" do
    test "gives correct ids for current role" do
      repo = create(:repository, :minimal, owner: @org)
      custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id)
      member, collab = create(:user), create(:user)

      @org.add_member(member, action: :write)
      repo.add_member(member, action: custom_role.name)
      repo.add_member(collab, action: custom_role.name)

      assert_same_elements [member.id], custom_role.org_member_ids
    end

    test "gives no ids for unassigned role" do
      another_custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id)
      assert_empty another_custom_role.org_member_ids
    end
  end

  context "#collaborator_ids" do
    test "gives correct ids for current role" do
      repo = create(:repository, :minimal, owner: @org)
      custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id)
      member, collab, collab2 = create(:user), create(:user), create(:user)

      @org.add_member(member, action: :write)
      repo.add_member(member, action: custom_role.name)
      repo.add_member(collab, action: custom_role.name)
      repo.add_member(collab2, action: "triage")

      assert_same_elements [collab.id], custom_role.collaborator_ids
    end

    test "gives no ids for unassigned role" do
      another_custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id)
      assert_empty another_custom_role.collaborator_ids
    end
  end

  test "#role_team_count" do
    repo = create(:repository, :minimal, owner: @org)
    custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id)
    another_custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id)

    team = create(:team, organization: @org, privacy: :closed)
    team2 = create(:team, organization: @org, privacy: :closed)
    team.add_repository repo, custom_role.name
    team2.add_repository repo, "write"

    assert_equal 1, custom_role.team_count
    assert_equal 0, @triage.team_count
    assert_equal 0, another_custom_role.team_count
  end

  test "instruments role create" do
    # Subscribing to an event action type.
    events = subscribe "role.create"

    create_custom_role(role_name: "developer", owner: @org, base_role: :read)

    expected_payload = {
      name: "developer",
      owner: "github",
      role_permissions: "None",
      base_role: "read",
      business: @org.business,
      org: @org.login,
      org_id: @org.id,
    }

    # Popping the most recent event from the subscription to "role.create".
    assert event = events.pop, "an event was expected"

    # Verifying the full shape of the event payload.
    assert_equal expected_payload, event.payload
  end

  test "instruments role delete/destroy" do
    # Subscribing to an event action type
    events = subscribe "role.destroy"

    role = create_custom_role(role_name: "developer", owner: @org, base_role: :write)
    role.destroy

    expected_payload = {
      name: "developer",
      owner: "github",
      role_permissions: "None",
      base_role: "write",
      business: @org.business,
      org: @org.login,
      org_id: @org.id,
    }

    # Popping the most recent event from the subscription to "role.create".
    assert event = events.pop, "an event was expected"

    # Verifying the full shape of the event payload.
    assert_equal expected_payload, event.payload
  end

  if GitHub.hydro_enabled?
    test "records a Hydro event when a repository custom role is successfully deleted" do
      custom_role = create_custom_role(role_name: "developer", owner: @org, base_role: :write)
      custom_role.destroy

      assert_hydro_published({
        role: Hydro::EntitySerializer.custom_repository_role(custom_role),
        org_custom_roles_count: 0
      }, schema: "github.custom_repository_roles.v0.CustomRepositoryRoleDeleted")
    end

    test "records a Hydro event when an organization custom role is successfully deleted" do
      custom_role = create(:custom_organization_role, owner_id: @org.id)
      custom_role.destroy

      assert_hydro_published({
        role: Hydro::EntitySerializer.custom_organization_role(custom_role),
        org_custom_org_roles_count: 0
      }, schema: "github.custom_organization_roles.v0.CustomOrganizationRoleDeleted")
    end

    test "does not record a Hydro event if a non-custom role is deleted" do
      Role.destroy Role.project_reader_role.id
      Role.destroy Role.write_role.id

      assert_hydro_messages(count: 0, schema: "github.custom_repository_roles.v0.CustomRepositoryRoleDeleted")
    end
  end

  test "system_repo_roles returns all system roles" do
    roles = Role.system_repo_roles
    assert_same_elements Role::RESERVED_NAMES, roles.map(&:name)
  end

  test "system_package_roles doesn't return custom roles with internal role names" do
    # custom roles could have the same name, but should not be returned in the result
    custom_role = create_custom_role(role_name: Role::PACKAGES_SYSTEM_ROLES.first, owner: @org)
    internal_roles = Role.system_package_roles
    refute_includes internal_roles, custom_role
  end

  test "primary_system_roles returns the primary system roles" do
    roles = Role.primary_system_repo_roles
    assert_same_elements Role::PRIMARY_REPO_BASE_ROLES, roles.map(&:name)
  end

  test "does not require description for custom roles" do
    org = create(:business_plus_organization)
    role = Role.create!(name: "developer", base_role_id: Role.triage_role.id, owner_id: org.id, owner_type: "Organization")

    assert_predicate role, :valid?
    assert role.errors[:description].empty?
  end

  context "emoji support" do
    test "create custom role name and description with emoji" do
      role_name = "😉 developer".b
      role_description = "😉 software engineering staff members".b

      role = assert_difference "Role.count" do
        Role.create(
          name: role_name,
          description: role_description,
          owner_id: @org.id,
          owner_type: "Organization",
          base_role_id: @triage.id, target_type: "Repository",
        )
      end
      assert_equal Encoding::UTF_8, role.name.encoding
      assert_equal Encoding::UTF_8, role.description.encoding
    end

    test "fails to create custom role if name and description values are too long " do
      role_name, role_description = "", ""
      63.times { role_name += "😉".b }
      153.times { role_description += "😉".b }
      role = build(:role, name: role_name, description: role_description, owner_id: @org.id,
        owner_type: "Organization", base_role_id: @triage.id)

      expected_response = "Name cannot be longer than 62 characters and Description cannot be longer than 152 characters"

      refute_predicate role, :valid?
      assert_equal expected_response, role.errors.full_messages.to_sentence
    end
  end

  context "role editing instrumentation" do
    test "generates a valid audit log entry" do
      events = subscribe "role.update"

      custom_role = create_custom_role(role_name: "developer", owner: @org, base_role: :read)
      custom_role.update! name: "intern", base_role_id: Role.write_role.id

      expected_payload = {
        name: "intern",
        owner: "github",
        role_permissions: "None",
        base_role: "write",
        business: @org.business,
        org: @org.login,
        org_id: @org.id,
        changes: {
          old_name: "developer",
          old_base_role: "read"
        },
        old_base_role: "read",
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    if GitHub.hydro_enabled?
      test "records a Hydro event if a custom repository role is updated successfully" do
        custom_role = create_custom_role(role_name: "developer", owner: @org, base_role: :read)
        custom_role.update! name: "intern", base_role_id: Role.write_role.id

        assert_hydro_published({
          role: Hydro::EntitySerializer.custom_repository_role(custom_role),
        }, schema: "github.custom_repository_roles.v0.CustomRepositoryRoleUpdated")
      end

      test "records a Hydro event if a custom organiation role is updated successfully" do
        custom_role = create(:custom_organization_role, owner_id: @org.id)
        custom_role.update! name: "new role name"

        assert_hydro_published({
          role: Hydro::EntitySerializer.custom_organization_role(custom_role)
        }, schema: "github.custom_organization_roles.v0.CustomOrganizationRoleUpdated")
      end

      test "does not record a Hydro event if a custom role was not updated successfully" do
        custom_role = create_custom_role(role_name: "developer", owner: @org, base_role: :read)
        # `maintain` is an invalid custom role name
        refute custom_role.update(name: "maintain", base_role_id: Role.write_role.id)

        assert_hydro_messages(count: 0, schema: "github.custom_repository_roles.v0.CustomRepositoryRoleUpdated")
      end

      test "does not record a Hydro event if a non-custom role is updated successfully" do
        Role.destroy Role.write_role.id
        read_role = Role.read_role
        assert read_role.update(name: "write")

        assert_hydro_messages(count: 0, schema: "github.custom_repository_roles.v0.CustomRepositoryRoleUpdated")
      end
    end

    test "generates an event for name changes" do
      events = subscribe "role.update"

      custom_role = create_custom_role(role_name: "developer", owner: @org, base_role: :read)
      custom_role.update! name: "intern"

      expected_payload = {
        name: "intern",
        owner: "github",
        role_permissions: "None",
        base_role: "read",
        business: @org.business,
        changes: {
          old_name: "developer"
        },
        org: @org.login,
        org_id: @org.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "generates an event for base role changes" do
      events = subscribe "role.update"

      custom_role = create_custom_role(role_name: "developer", owner: @org, base_role: :read)
      custom_role.update! base_role_id: Role.write_role.id

      expected_payload = {
        name: "developer",
        owner: "github",
        role_permissions: "None",
        base_role: "write",
        business: @org.business,
        changes: {
          old_base_role: "read"
        },
        old_base_role: "read",
        org: @org.login,
        org_id: @org.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "does not generate event for description changes" do
      events = subscribe "role.update"

      custom_role = create_custom_role(role_name: "developer", owner: @org, base_role: :read)
      custom_role.update! description: "foo"

      refute event = events.pop, "no event was expected"
    end

    context "with emoji" do
      test "the old name contains an emoji, and the new name doesn't" do
        custom_role = create_custom_role(role_name: "🛠 developer", owner: @org, base_role: :read)

        events = subscribe "role.update"
        custom_role.update! name: "developer"

        expected_payload = {
          name: "developer",
          owner: "github",
          role_permissions: "None",
          base_role: "read",
          business: @org.business,
          org: @org.login,
          org_id: @org.id,
          changes: {
            old_name: "🛠 developer",
          },
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "the old name doesn't contain emoji, the new name does" do
        events = subscribe "role.update"

        custom_role = create_custom_role(role_name: "developer", owner: @org, base_role: :read)
        custom_role.update! name: "🛠 developer"

        expected_payload = {
          name: "🛠 developer",
          owner: "github",
          role_permissions: "None",
          base_role: "read",
          business: @org.business,
          org: @org.login,
          org_id: @org.id,
          changes: {
            old_name: "developer",
          },
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "both names have emoji, but different emoji" do
        events = subscribe "role.update"

        custom_role = create_custom_role(role_name: "developer 🛠", owner: @org, base_role: :read)
        custom_role.update! name: "🛠 developer"

        expected_payload = {
          name: "🛠 developer",
          owner: "github",
          role_permissions: "None",
          base_role: "read",
          business: @org.business,
          org: @org.login,
          org_id: @org.id,
          changes: {
            old_name: "developer 🛠",
          },
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "both have the same name with same emoji" do
        events = subscribe "role.update"

        custom_role = create_custom_role(role_name: "🛠 developer", owner: @org, base_role: :read)
        custom_role.update! name: "🛠 developer"

        refute events.pop, "no event was expected"
      end

      test "a change in only the description field doesn't trigger an event" do
        events = subscribe "role.update"

        custom_role = create_custom_role(role_name: "developer 🛠", owner: @org, base_role: :read)
        custom_role.update! description: "🛠 foo"

        refute events.pop, "no event was expected"
      end
    end
  end

  context ".lower_custom_role_ids" do
    test "returns array of organization custom role ids" do
      custom_roles = []
      2.times { custom_roles.push(create_custom_role(owner: @org, base_role: :read)) }

      expected_results = custom_roles.map(&:id)
      actual_results = RepositoryRole.lower_custom_role_ids(action: @write.name, org: @org)

      assert_same_elements expected_results, actual_results
    end

    test "returns empty array if 'none' is passed as action" do
      create_custom_role(owner: @org, base_role: :read)
      results = RepositoryRole.lower_custom_role_ids(action: "none", org: @org)

      assert_predicate results, :empty?
    end

    test "returns empty array if all custom roles have higher ranked base role" do
      create_custom_role(owner: @org, base_role: :maintain)
      results = RepositoryRole.lower_custom_role_ids(action: @write.name, org: @org)

      assert_predicate results, :empty?
    end

    test "returns empty array if another org is passed into the method" do
      another_org = create(:business_plus_organization)
      create_custom_role(owner: @org, base_role: :read)

      results = RepositoryRole.lower_custom_role_ids(action: @write.name, org: another_org)

      assert_predicate results, :empty?
    end

    test "returns empty array if action is a custom role" do
      custom_role = create_custom_role(owner: @org, base_role: :read)
      results = RepositoryRole.lower_custom_role_ids(action: custom_role.name, org: @org)

      assert_predicate results, :empty?
    end

    test "returns empty array if action is illegal" do
      results = RepositoryRole.lower_custom_role_ids(action: "foo", org: @org)
      assert_predicate results, :empty?
    end

    test "returns empty array if action is nil" do
      results = RepositoryRole.lower_custom_role_ids(action: nil, org: @org)
      assert_predicate results, :empty?
    end
  end

  context "#all_dependencies_updated?" do
    test "returns false if custom role has dependencies" do
      repo = create(:repository, :minimal, owner: @org)
      custom_role = create_custom_role(owner: @org, base_role: :read)
      member = create(:user)
      @org.add_member(member)
      repo.add_member(member, action: custom_role.name)

      refute custom_role.all_dependencies_updated?
    end

    test "return true if custom role has no dependencies" do
      custom_role = create_custom_role(owner: @org, base_role: :read)

      assert custom_role.all_dependencies_updated?
    end

    test "raises error if it is not a custom role" do
      assert_raises Role::CustomRoleError do
        @read.all_dependencies_updated?
      end
    end
  end

  context ".by_name" do
    test "finds system roles" do
      assert_equal @write, RepositoryRole.by_name(perm: "write", org: @org)
      assert_equal @write, RepositoryRole.by_name(perm: "push", org: @org)
      assert_equal @read, RepositoryRole.by_name(perm: "read", org: @org)
      assert_equal @read, RepositoryRole.by_name(perm: "pull", org: @org)
      assert_equal @maintain, RepositoryRole.by_name(perm: "maintain", org: @org)
      assert_equal @admin, RepositoryRole.by_name(perm: "admin", org: @org)
      assert_equal @triage, RepositoryRole.by_name(perm: "triage", org: @org)
    end

    test "does not find internal roles" do
      assert_nil RepositoryRole.by_name(perm: "package_writer", org: @org)
    end

    test "finds nothing system role base roles" do
      assert_nil RepositoryRole.by_name(perm: "write", org: @org, retrieve_base_role: true)
      assert_nil RepositoryRole.by_name(perm: "read", org: @org, retrieve_base_role: true)
      assert_nil RepositoryRole.by_name(perm: "maintain", org: @org, retrieve_base_role: true)
      assert_nil RepositoryRole.by_name(perm: "admin", org: @org, retrieve_base_role: true)
      assert_nil RepositoryRole.by_name(perm: "triage", org: @org, retrieve_base_role: true)
    end

    test "finds a custom role role by name" do
      role = create_custom_role(role_name: "😉 foo", owner: @org, base_role: :read)

      assert_equal role, RepositoryRole.by_name(perm: role.name, org: @org)
    end

    test "finds a custom role role with the name of an internal role" do
      role = create_custom_role(role_name: "package_writer", owner: @org, base_role: :read)

      assert_equal role, RepositoryRole.by_name(perm: role.name, org: @org)
    end

    test "finds a custom role base role by name" do
      read_role = create_custom_role(role_name: "😉 foo", owner: @org, base_role: :read)
      maintain_role = create_custom_role(role_name: "😉 foo2", owner: @org, base_role: :maintain)

      assert_equal Role.read_role, RepositoryRole.by_name(perm: read_role.name, org: @org, retrieve_base_role: true)
      assert_equal Role.maintain_role, RepositoryRole.by_name(perm: maintain_role.name, org: @org, retrieve_base_role: true)
    end

    test "returns a nil for non existent role" do
      assert_nil RepositoryRole.by_name(perm: "non existent", org: @org)
      assert_nil RepositoryRole.by_name(perm: "non existent", org: @org, retrieve_base_role: true)


      assert_nil RepositoryRole.by_name(perm: "raed", org: @org)
      assert_nil RepositoryRole.by_name(perm: "wirte", org: @org, retrieve_base_role: true)
    end
  end

  context "self.error_message_from_exception" do
    test "returns expected error message for FGPsNotSupportedError" do
      repo = create(:repository, :minimal, owner: @org)
      assert_equal "Role `triage` is not supported under the current billing plan.",
        Role.error_message_from_exception(Role::FGPsNotSupportedError.new,
                                          permission: :triage, repository: repo)
    end

    test "returns expected error message for InvalidPermissionError" do
      repo = create(:repository, :minimal, owner: @org)
      assert_equal "`invalid` is not a valid permission.",
        Role.error_message_from_exception(Role::InvalidPermissionError.new,
                                          permission: :invalid, repository: repo)
    end

    test "returns expected error message for InvalidCustomRoleError" do
      repo = create(:repository, :minimal, owner: @org)
      assert_equal "Role `custom-role` is not available for the #{repo.name_with_owner} repository.",
      Role.error_message_from_exception(Role::InvalidCustomRoleError.new,
                                        permission: "custom-role", repository: repo)
    end

    test "returns nil for an unsupported error" do
      assert_nil Role.error_message_from_exception(ArgumentError.new, permission: "", repository: nil)
    end
  end

  context "RepositoryRole" do
    test "has target_type" do
      cr = Role.create!(
        name: "test repo role",
        description: "test test repo role description",
        owner_id: @org.id,
        owner_type: "Organization",
        base_role_id: Role.triage_role.id,
        target_type: "Repository"
      )

      assert cr.instance_of?(RepositoryRole)
    end
  end

  context "OrganizationRole" do
    test "has target_type" do
      cr = Role.create!(
        name: "test org role",
        description: "test org role description",
        owner_id: @org.id,
        owner_type: "Organization",
        base_role_id: nil,
        target_type: "Organization"
      )

      assert cr.instance_of?(OrganizationRole)
    end
  end

  context "EnterpriseRole" do
    test "has target_type" do
      mod_sys_roles = Role::SYSTEM_ROLES + %w(test_enterprise_role)
      Role.stub_const(:SYSTEM_ROLES, mod_sys_roles) do # We don't have a real enterprise role yet
        cr = Role.create!(
          name: "test_enterprise_role",
          target_type: "Business"
        )

        assert cr.instance_of?(EnterpriseRole)
      end
    end
  end

  context "#base_role_ids_to_name" do
    test "returns correct values and memoizes correctly" do
      GitHub::MysqlInstrumenter.reset_stats
      GitHub::MysqlInstrumenter.with_track do
        assert_equal Role.base_role_ids_to_name[@read.id], @read.name
        assert_equal Role.base_role_ids_to_name[@triage.id], @triage.name
        assert_equal Role.base_role_ids_to_name[@write.id], @write.name
        assert_equal Role.base_role_ids_to_name[@maintain.id], @maintain.name
        assert_equal Role.base_role_ids_to_name[@admin.id], @admin.name
        assert_operator GitHub::MysqlInstrumenter.query_count, :<=, 1
      end
    end
  end
end
