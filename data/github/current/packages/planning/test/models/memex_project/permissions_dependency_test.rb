# typed: true
# frozen_string_literal: true
require "test_helper"

class PermissionsDependencyTest < GitHub::TestCase
  fixtures do
    @admin  = create(:verified_user)
    @org    = create(:enterprise_linked_organization, admin: @admin)

    @installation = make_integration_installation(target: @org, permissions: { "organization_projects" => :write })

    @non_member = create(:verified_user)

    @org_member = create(:verified_user)
    @org.add_member(@org_member)

    @team = create(:team, organization: @org)
    @team.add_member @org_member

    @user   = create(:verified_user)

    @memex = create(:memex_project, owner: @org, title: "My Memex Project")
    @user_owned_memex = create(:memex_project, owner: @user)

    MemexHelpers.setup_organization_wide_access_for_projects("project_writer")
  end

  context "grant_role" do
    test "granting :reader" do
      [@user, @team].each do |actor|
        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_reader_role)

        @memex.grant_role(actor, :reader)

        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_reader_role).map(&:actor)
      end
    end

    test "granting project_reader" do
      [@user, @team].each do |actor|
        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_reader_role)

        @memex.grant_role(actor, "project_reader")

        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_reader_role).map(&:actor)
      end
    end

    test "granting Role.project_reader_role" do
      [@user, @team].each do |actor|
        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_reader_role)

        @memex.grant_role(actor, Role.project_reader_role)

        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_reader_role).map(&:actor)
      end
    end

    test "granting :writer" do
      [@user, @team].each do |actor|
        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_writer_role)

        @memex.grant_role(actor, :writer)

        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_writer_role).map(&:actor)
      end
    end

    test "granting project_writer" do
      [@user, @team].each do |actor|
        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_writer_role)

        @memex.grant_role(actor, "project_writer")

        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_writer_role).map(&:actor)
      end
    end

    test "granting Role.project_writer_role" do
      [@user, @team].each do |actor|
        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_writer_role)

        @memex.grant_role(actor, Role.project_writer_role)

        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_writer_role).map(&:actor)
      end
    end

    test "granting :admin" do
      [@user, @team].each do |actor|
        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_admin_role)

        @memex.grant_role(actor, :admin)

        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_admin_role).map(&:actor)
      end
    end

    test "granting project_admin" do
      [@user, @team].each do |actor|
        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_admin_role)

        @memex.grant_role(actor, "project_admin")

        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_admin_role).map(&:actor)
      end
    end

    test "granting Role.project_admin_role" do
      [@user, @team].each do |actor|
        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_admin_role)

        @memex.grant_role(actor, Role.project_admin_role)

        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_admin_role).map(&:actor)
      end
    end

    test "granting invalid role name throws" do
      assert_raises_with_message(ArgumentError, "Invalid role name: test_test") do
        @memex.grant_role(@user, :test_test)
      end

      assert_raises_with_message(ArgumentError, "Invalid role name: project_test") do
        @memex.grant_role(@user, :project_test)
      end
    end

    test "granting invalid role for projects throws" do
      assert_raises_with_message(ArgumentError, "Not a project role: read") do
        @memex.grant_role(@user, Role.read_role)
      end
    end
  end

  context "revoke_role" do
    test "revoking :reader role" do
      [@user, @team].each do |actor|
        Permissions::Granters::RoleGranter.new(actor: actor, target: @memex, role: Role.project_reader_role).grant!
        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_reader_role).map(&:actor)

        @memex.revoke_role(actor, :reader)

        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_reader_role)
      end
    end

    test "revoking project_reader role" do
      [@user, @team].each do |actor|
        Permissions::Granters::RoleGranter.new(actor: actor, target: @memex, role: Role.project_reader_role).grant!
        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_reader_role).map(&:actor)

        @memex.revoke_role(actor, "project_reader")

        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_reader_role)
      end
    end

    test "revoking Role.project_reader_role" do
      [@user, @team].each do |actor|
        Permissions::Granters::RoleGranter.new(actor: actor, target: @memex, role: Role.project_reader_role).grant!
        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_reader_role).map(&:actor)

        @memex.revoke_role(actor, Role.project_reader_role)

        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_reader_role)
      end
    end

    test "revoking :writer role" do
      [@user, @team].each do |actor|
        Permissions::Granters::RoleGranter.new(actor: actor, target: @memex, role: Role.project_writer_role).grant!
        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_writer_role).map(&:actor)

        @memex.revoke_role(actor, :writer)

        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_writer_role)
      end
    end

    test "revoking project_writer role" do
      [@user, @team].each do |actor|
        Permissions::Granters::RoleGranter.new(actor: actor, target: @memex, role: Role.project_writer_role).grant!
        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_writer_role).map(&:actor)

        @memex.revoke_role(actor, "project_writer")

        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_writer_role)
      end
    end

    test "revoking Role.project_writer_role" do
      [@user, @team].each do |actor|
        Permissions::Granters::RoleGranter.new(actor: actor, target: @memex, role: Role.project_writer_role).grant!
        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_writer_role).map(&:actor)

        @memex.revoke_role(actor, Role.project_writer_role)

        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_writer_role)
      end
    end

    test "revoking :admin role" do
      [@user, @team].each do |actor|
        Permissions::Granters::RoleGranter.new(actor: actor, target: @memex, role: Role.project_admin_role).grant!
        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_admin_role).map(&:actor)

        @memex.revoke_role(actor, :admin)

        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_admin_role)
      end
    end

    test "revoking project_admin role" do
      [@user, @team].each do |actor|
        Permissions::Granters::RoleGranter.new(actor: actor, target: @memex, role: Role.project_admin_role).grant!
        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_admin_role).map(&:actor)

        @memex.revoke_role(actor, "project_admin")

        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_admin_role)
      end
    end

    test "revoking Role.project_admin_role" do
      [@user, @team].each do |actor|
        Permissions::Granters::RoleGranter.new(actor: actor, target: @memex, role: Role.project_admin_role).grant!
        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_admin_role).map(&:actor)

        @memex.revoke_role(actor, Role.project_admin_role)

        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_admin_role)
      end
    end

    test "revoking role when none was granted before" do
      [@user, @team].each do |actor|
        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_writer_role).map(&:actor)

        @memex.revoke_role(actor, :writer)

        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_writer_role)
      end
    end

    test "revoking role does not revoke other roles" do
      [@user, @team].each do |actor|
        Permissions::Granters::RoleGranter.new(actor: actor, target: @memex, role: Role.project_admin_role).grant!

        @memex.revoke_role(actor, :writer)

        assert_empty fetch_roles_for(project: @memex, actor: actor, role: Role.project_writer_role)
        assert_equal [actor], fetch_roles_for(project: @memex, actor: actor, role: Role.project_admin_role).map(&:actor)
      end
    end

    test "revoking invalid role name throws" do
      assert_raises_with_message(ArgumentError, "Invalid role name: test_test") do
        @memex.revoke_role(@user, :test_test)
      end

      assert_raises_with_message(ArgumentError, "Invalid role name: project_test") do
        @memex.revoke_role(@user, :project_test)
      end
    end

    test "revoking invalid role for projects throws" do
      assert_raises_with_message(ArgumentError, "Not a project role: read") do
        @memex.revoke_role(@user, Role.read_role)
      end
    end
  end

  context "update_organization_wide_role" do
    test "sets org wide role for org owned memex" do
      updater   = create(:verified_user)

      assert_nil ::Configuration::Entry.find_by(target_id: @memex.id, target_type: "MemexProject", name: "memex_project_organization_wide_role")

      @memex.update_organization_wide_role("project_reader", updater)

      assert_equal "project_reader", ::Configuration::Entry.find_by(target_id: @memex.id, target_type: "MemexProject", name: "memex_project_organization_wide_role")&.value

      @memex.update_organization_wide_role("project_writer", updater)

      assert_equal "project_writer", ::Configuration::Entry.find_by(target_id: @memex.id, target_type: "MemexProject", name: "memex_project_organization_wide_role")&.value

      @memex.update_organization_wide_role("project_admin", updater)

      assert_equal "project_admin", ::Configuration::Entry.find_by(target_id: @memex.id, target_type: "MemexProject", name: "memex_project_organization_wide_role")&.value

      @memex.update_organization_wide_role("none", updater)

      assert_equal "none", ::Configuration::Entry.find_by(target_id: @memex.id, target_type: "MemexProject", name: "memex_project_organization_wide_role")&.value
    end

    test "no-op if called on user owned memex" do
      updater = create(:verified_user)
      user_memex  = create(:memex_project, owner: updater)

      assert_nil ::Configuration::Entry.find_by(target_id: user_memex.id, target_type: "MemexProject", name: "memex_project_organization_wide_role")

      user_memex.update_organization_wide_role("project_reader", updater)

      assert_nil ::Configuration::Entry.find_by(target_id: user_memex.id, target_type: "MemexProject", name: "memex_project_organization_wide_role")
    end

    test "setting invalid role name throws" do
      updater   = create(:verified_user)
      assert_raises_with_message(ArgumentError, "Invalid role name: test_test") do
        @memex.update_organization_wide_role(:test_test, updater)
      end
    end
  end

  context "organization_wide_role" do
    test "returns global setting by default" do
      config_entry = ::Configuration::Entry.find_by(target_type: "global", name: "memex_project_organization_wide_role")
      refute_nil config_entry
      assert_equal config_entry&.value, @memex.organization_wide_role
    end

    test "returns org-wide setting if set" do
      updater = create(:verified_user)

      ::Configuration::Entry.create!(
        target_id: @memex.id,
        target_type: "MemexProject",
        updater: updater,
        name: "memex_project_organization_wide_role",
        value: "project_reader"
      )

      assert_equal "project_reader", @memex.organization_wide_role
    end

    test "returns project setting if set" do
      updater = create(:verified_user)

      ::Configuration::Entry.create!(
        target_id: @memex.id,
        target_type: "MemexProject",
        updater: updater,
        name: "memex_project_organization_wide_role",
        value: "none"
      )

      assert_equal "none", @memex.organization_wide_role
    end

    test "returns none if no setting exists" do
      ::Configuration::Entry.destroy_all
      assert_nil ::Configuration::Entry.find_by(name: "memex_project_organization_wide_role")
      assert_equal "none", @memex.organization_wide_role
    end
  end

  context "#(async_)viewer_can_read?" do
    context "user owned projects" do
      test "owner can read the project" do
        assert @user_owned_memex.async_viewer_can_read?(@user).sync
        assert @user_owned_memex.viewer_can_read?(@user)
        assert @user_owned_memex.async_readable_by?(@user).sync
        assert @user_owned_memex.readable_by?(@user)
      end

      test "non-owner cannot read the project" do
        refute @user_owned_memex.async_viewer_can_read?(@non_member).sync
        refute @user_owned_memex.viewer_can_read?(@non_member)
        refute @user_owned_memex.async_readable_by?(@non_member).sync
        refute @user_owned_memex.readable_by?(@non_member)
      end

      test "collaborators can read the project" do
        @user_owned_memex.grant_role(@non_member, Role.project_reader_role)
        assert @user_owned_memex.async_viewer_can_read?(@non_member).sync
        assert @user_owned_memex.viewer_can_read?(@non_member)
        assert @user_owned_memex.async_readable_by?(@non_member).sync
        assert @user_owned_memex.readable_by?(@non_member)
      end

      test "non-owner can read public projects" do
        @user_owned_memex.update!(public: true)
        assert @user_owned_memex.async_viewer_can_read?(@non_member).sync
        assert @user_owned_memex.viewer_can_read?(@non_member)
        assert @user_owned_memex.async_readable_by?(@non_member).sync
        assert @user_owned_memex.readable_by?(@non_member)
      end

      test "anonymous user can read public projects" do
        @user_owned_memex.update!(public: true)
        assert @user_owned_memex.async_viewer_can_read?(nil).sync
        assert @user_owned_memex.viewer_can_read?(nil)
        assert @user_owned_memex.async_readable_by?(nil).sync
        assert @user_owned_memex.readable_by?(nil)
      end

      test "integration installations cannot read the project" do
        refute @user_owned_memex.async_viewer_can_read?(@installation).sync
        refute @user_owned_memex.viewer_can_read?(@installation)
        refute @user_owned_memex.async_readable_by?(@installation).sync
        refute @user_owned_memex.readable_by?(@installation)
      end

      test "anonymous user cannot read public EMU-owned project" do
        GitHub.flipper[:memex_no_public_emu_projects].disable
        owner = create(:emu)
        emu_user_owned_memex = create(:memex_project, public: true, owner:)

        refute emu_user_owned_memex.async_viewer_can_read?(nil).sync
        refute emu_user_owned_memex.viewer_can_read?(nil)
        refute emu_user_owned_memex.async_readable_by?(nil).sync
        refute emu_user_owned_memex.readable_by?(nil)
      end unless GitHub.single_business_environment?

      test "fellow enterprise member can read public EMU-owned project" do
        GitHub.flipper[:memex_no_public_emu_projects].disable

        owner = create(:emu)
        other_emu = create(:emu, business: owner.enterprise_managed_business)
        orgs = create_list(:enterprise_linked_organization, 2, business: owner.enterprise_managed_business)
        orgs.first.add_member(owner)
        orgs.second.add_member(other_emu)

        assert_equal owner.enterprise_managed_business, other_emu.enterprise_managed_business
        refute orgs.first.member?(other_emu)
        refute orgs.second.member?(owner)

        emu_user_owned_memex = create(:memex_project, public: true, owner:)

        assert emu_user_owned_memex.async_viewer_can_read?(other_emu).sync
        assert emu_user_owned_memex.viewer_can_read?(other_emu)
        assert emu_user_owned_memex.async_readable_by?(other_emu).sync
        assert emu_user_owned_memex.readable_by?(other_emu)
      end unless GitHub.single_business_environment?

      test "user from different enterprise cannot read public EMU-owned project" do
        GitHub.flipper[:memex_no_public_emu_projects].disable

        owner = create(:emu)
        unrelated_emu = create(:emu)
        refute_equal owner.enterprise_managed_business, unrelated_emu.enterprise_managed_business

        emu_user_owned_memex = create(:memex_project, public: true, owner:)

        refute emu_user_owned_memex.async_viewer_can_read?(unrelated_emu).sync
        refute emu_user_owned_memex.viewer_can_read?(unrelated_emu)
        refute emu_user_owned_memex.async_readable_by?(unrelated_emu).sync
        refute emu_user_owned_memex.readable_by?(unrelated_emu)
      end unless GitHub.single_business_environment?
    end

    context "org owned projects" do
      test "org admin can read the project" do
        assert @memex.async_viewer_can_read?(@org.admins.first).sync
        assert @memex.viewer_can_read?(@org.admins.first)
        assert @memex.async_readable_by?(@org.admins.first).sync
        assert @memex.readable_by?(@org.admins.first)
      end

      test "org member can read the project if org wide access is set to read" do
        MemexHelpers::setup_organization_wide_access("project_reader", @memex)
        assert @memex.async_viewer_can_read?(@org_member).sync
        assert @memex.viewer_can_read?(@org_member)
        assert @memex.async_readable_by?(@org_member).sync
        assert @memex.readable_by?(@org_member)
      end

      test "org member cannot read the project if org wide access is set to none" do
        MemexHelpers::setup_organization_wide_access("none", @memex)
        refute @memex.async_viewer_can_read?(@org_member).sync
        refute @memex.viewer_can_read?(@org_member)
        refute @memex.async_readable_by?(@org_member).sync
        refute @memex.readable_by?(@org_member)
      end

      test "read collaborators can read the memex" do
        MemexHelpers::setup_organization_wide_access("none", @memex)
        @memex.grant_role(@non_member, Role.project_reader_role)
        assert @memex.async_viewer_can_read?(@non_member).sync
        assert @memex.viewer_can_read?(@non_member)
        assert @memex.async_readable_by?(@non_member).sync
        assert @memex.readable_by?(@non_member)
      end

      test "non member cannot read the project" do
        refute @memex.async_viewer_can_read?(@non_member).sync
        refute @memex.viewer_can_read?(@non_member)
        refute @memex.async_readable_by?(@non_member).sync
        refute @memex.readable_by?(@non_member)
      end

      test "non member can read public projects project" do
        @memex.update!(public: true)
        assert @memex.async_viewer_can_read?(@non_member).sync
        assert @memex.viewer_can_read?(@non_member)
        assert @memex.async_readable_by?(@non_member).sync
        assert @memex.readable_by?(@non_member)
      end

      test "anonymous user can read public projects project" do
        @memex.update!(public: true)
        assert @memex.async_viewer_can_read?(nil).sync
        assert @memex.viewer_can_read?(nil)
        assert @memex.async_readable_by?(nil).sync
        assert @memex.readable_by?(nil)
      end

      test "integration installations can read the project" do
        assert @memex.async_viewer_can_read?(@installation).sync
        assert @memex.viewer_can_read?(@installation)
        assert @memex.async_readable_by?(@installation).sync
        assert @memex.readable_by?(@installation)
      end

      test "anonymous user cannot read public EMU-owned project" do
        GitHub.flipper[:memex_no_public_emu_projects].disable
        admin = create(:emu)
        emu_org = create(:organization, business: admin.enterprise_managed_business)

        emu_org_owned_memex = create(:memex_project, public: true, owner: emu_org)

        refute emu_org_owned_memex.async_viewer_can_read?(nil).sync
        refute emu_org_owned_memex.viewer_can_read?(nil)
        refute emu_org_owned_memex.async_readable_by?(nil).sync
        refute emu_org_owned_memex.readable_by?(nil)
      end unless GitHub.single_business_environment?

      test "fellow enterprise member can read public EMU-owned project" do
        GitHub.flipper[:memex_no_public_emu_projects].disable

        emu = create(:emu)
        other_emu = create(:emu, business: emu.enterprise_managed_business)
        orgs = create_list(:enterprise_linked_organization, 2, business: emu.enterprise_managed_business)
        orgs.first.add_member(emu)
        orgs.second.add_member(other_emu)

        assert_equal emu.enterprise_managed_business, other_emu.enterprise_managed_business
        refute orgs.first.member?(other_emu)
        refute orgs.second.member?(emu)

        emu_org_owned_memex = create(:memex_project, public: true, owner: orgs.first)

        assert emu_org_owned_memex.async_viewer_can_read?(other_emu).sync
        assert emu_org_owned_memex.viewer_can_read?(other_emu)
        assert emu_org_owned_memex.async_readable_by?(other_emu).sync
        assert emu_org_owned_memex.readable_by?(other_emu)
      end unless GitHub.single_business_environment?

      test "user from different enterprise cannot read public EMU-owned project" do
        GitHub.flipper[:memex_no_public_emu_projects].disable

        admin = create(:emu)
        emu_org = create(:organization, business: admin.enterprise_managed_business)

        unrelated_emu = create(:emu)
        refute_equal admin.enterprise_managed_business, unrelated_emu.enterprise_managed_business

        emu_org_owned_memex = create(:memex_project, public: true, owner: emu_org)

        refute emu_org_owned_memex.async_viewer_can_read?(unrelated_emu).sync
        refute emu_org_owned_memex.viewer_can_read?(unrelated_emu)
        refute emu_org_owned_memex.async_readable_by?(unrelated_emu).sync
        refute emu_org_owned_memex.readable_by?(unrelated_emu)
      end unless GitHub.single_business_environment?
    end
  end

  context "#(async_)viewer_can_write?" do
    context "user owned projects" do
      test "owner can update the project" do
        assert @user_owned_memex.async_viewer_can_write?(@user).sync
        assert @user_owned_memex.viewer_can_write?(@user)
        assert @user_owned_memex.async_viewer_can_update?(@user).sync
      end

      test "non-owner cannot update the project" do
        refute @user_owned_memex.async_viewer_can_write?(@non_member).sync
        refute @user_owned_memex.viewer_can_write?(@non_member)
        refute @user_owned_memex.async_viewer_can_update?(@non_member).sync
      end

      test "write collaborators can update the project" do
        @user_owned_memex.grant_role(@non_member, Role.project_writer_role)
        assert @user_owned_memex.async_viewer_can_write?(@non_member).sync
        assert @user_owned_memex.viewer_can_write?(@non_member)
        assert @user_owned_memex.async_viewer_can_update?(@non_member).sync
      end

      test "non-owner cannot write public projects" do
        @user_owned_memex.update!(public: true)
        refute @user_owned_memex.async_viewer_can_write?(@non_member).sync
        refute @user_owned_memex.viewer_can_write?(@non_member)
        refute @user_owned_memex.async_viewer_can_update?(@non_member).sync
      end

      test "integration installations cannot update the project" do
        refute @user_owned_memex.async_viewer_can_update?(@installation).sync
        refute @user_owned_memex.async_viewer_can_write?(@installation).sync
        refute @user_owned_memex.viewer_can_write?(@installation)
      end
    end

    context "org owned projects" do
      test "org admin can update the project" do
        assert @memex.async_viewer_can_write?(@org.admins.first).sync
        assert @memex.viewer_can_write?(@org.admins.first)
        assert @memex.async_viewer_can_update?(@org.admins.first).sync
      end

      test "org member cannot update the project if org wide access is set to read" do
        MemexHelpers::setup_organization_wide_access("project_reader", @memex)
        refute @memex.async_viewer_can_write?(@org_member).sync
        refute @memex.viewer_can_write?(@org_member)
        refute @memex.async_viewer_can_update?(@org_member).sync
      end

      test "org member can update the project if org wide access is set to write" do
        MemexHelpers::setup_organization_wide_access("project_writer", @memex)
        assert @memex.async_viewer_can_write?(@org_member).sync
        assert @memex.viewer_can_write?(@org_member)
        assert @memex.async_viewer_can_update?(@org_member).sync
      end

      test "org member cannot update the project if org wide access is set to none" do
        MemexHelpers::setup_organization_wide_access("none", @memex)
        refute @memex.async_viewer_can_write?(@org_member).sync
        refute @memex.viewer_can_write?(@org_member)
        refute @memex.async_viewer_can_update?(@org_member).sync
      end

      test "write collaborators can update the memex" do
        MemexHelpers::setup_organization_wide_access("none", @memex)
        @memex.grant_role(@non_member, Role.project_writer_role)
        assert @memex.async_viewer_can_write?(@non_member).sync
        assert @memex.viewer_can_write?(@non_member)
        assert @memex.async_viewer_can_update?(@non_member).sync
      end

      test "non member cannot update the project" do
        refute @memex.async_viewer_can_write?(@non_member).sync
        refute @memex.viewer_can_write?(@non_member)
        refute @memex.async_viewer_can_update?(@non_member).sync
      end

      test "non member cannot update public projects project" do
        @memex.update!(public: true)
        refute @memex.async_viewer_can_write?(@non_member).sync
        refute @memex.viewer_can_write?(@non_member)
        refute @memex.async_viewer_can_update?(@non_member).sync
      end

      test "integration installations can update the project" do
        assert @memex.async_viewer_can_update?(@installation).sync
        assert @memex.async_viewer_can_write?(@installation).sync
        assert @memex.viewer_can_write?(@installation)
      end
    end
  end

  context "#(async_)viewer_is_admin?" do
    context "user owned projects" do
      test "owner can admin the project" do
        assert @user_owned_memex.async_viewer_is_admin?(@user).sync
        assert @user_owned_memex.viewer_is_admin?(@user)
      end

      test "non-owner cannot admin the project" do
        refute @user_owned_memex.async_viewer_is_admin?(@non_member).sync
        refute @user_owned_memex.viewer_is_admin?(@non_member)
      end

      test "write collaborators cannot admin the project" do
        @user_owned_memex.grant_role(@non_member, Role.project_writer_role)
        refute @user_owned_memex.async_viewer_is_admin?(@non_member).sync
        refute @user_owned_memex.viewer_is_admin?(@non_member)
      end

      test "admin collaborators can admin the project" do
        @user_owned_memex.grant_role(@non_member, Role.project_admin_role)
        assert @user_owned_memex.async_viewer_is_admin?(@non_member).sync
        assert @user_owned_memex.viewer_is_admin?(@non_member)
      end

      test "non-owner cannot admin public projects" do
        @user_owned_memex.update!(public: true)
        refute @user_owned_memex.async_viewer_is_admin?(@non_member).sync
        refute @user_owned_memex.viewer_is_admin?(@non_member)
      end
    end

    context "org owned projects" do
      test "org admin can admin the project" do
        assert @memex.async_viewer_is_admin?(@org.admins.first).sync
        assert @memex.viewer_is_admin?(@org.admins.first)
      end

      test "org member cannot admin the project if org wide access is set to write" do
        MemexHelpers::setup_organization_wide_access("project_writer", @memex)
        refute @memex.async_viewer_is_admin?(@org_member).sync
        refute @memex.viewer_is_admin?(@org_member)
      end

      test "org member can admin the project if org wide access is set to admin" do
        MemexHelpers::setup_organization_wide_access("project_admin", @memex)
        assert @memex.async_viewer_is_admin?(@org_member).sync
        assert @memex.viewer_is_admin?(@org_member)
      end

      test "org member cannot admin the project if org wide access is set to none" do
        MemexHelpers::setup_organization_wide_access("none", @memex)
        refute @memex.async_viewer_is_admin?(@org_member).sync
        refute @memex.viewer_is_admin?(@org_member)
      end

      test "write collaborators can admin the memex" do
        MemexHelpers::setup_organization_wide_access("none", @memex)
        @memex.grant_role(@non_member, Role.project_writer_role)
        refute @memex.async_viewer_is_admin?(@non_member).sync
        refute @memex.viewer_is_admin?(@non_member)
      end

      test "admin collaborators can admin the memex" do
        MemexHelpers::setup_organization_wide_access("none", @memex)
        @memex.grant_role(@non_member, Role.project_admin_role)
        assert @memex.async_viewer_is_admin?(@non_member).sync
        assert @memex.viewer_is_admin?(@non_member)
      end

      test "non member cannot admin the project" do
        refute @memex.async_viewer_is_admin?(@non_member).sync
        refute @memex.viewer_is_admin?(@non_member)
      end

      test "non member cannot admin public projects project" do
        @memex.update!(public: true)
        refute @memex.async_viewer_is_admin?(@non_member).sync
        refute @memex.viewer_is_admin?(@non_member)
      end
    end
  end

  context "#(async_)viewer_most_capable_permission" do
    test "returns :admin when viewer is an admin" do
      assert_equal :admin, @memex.viewer_most_capable_permission(@admin)
      assert_equal :admin, @memex.async_viewer_most_capable_permission(@admin).sync
    end

    test "returns :writer when viewer is a writer" do
      assert_equal :write, @memex.viewer_most_capable_permission(@org_member)
      assert_equal :write, @memex.async_viewer_most_capable_permission(@org_member).sync
    end

    test "returns :read when viewer is an reader" do
      @memex.update_organization_wide_role("project_reader", @admin)
      assert_equal :read, @memex.viewer_most_capable_permission(@org_member)
      assert_equal :read, @memex.async_viewer_most_capable_permission(@org_member).sync
    end

    test "returns :none when viewer cannot access the project" do
      @rando = create(:user)
      @memex.update!(public: false)

      assert_equal :none, @memex.viewer_most_capable_permission(@rando)
      assert_equal :none, @memex.async_viewer_most_capable_permission(@rando).sync
    end
  end

  context "#(async_)viewer_can_change_visibility?" do
    test "returns true for an org admin even when org denies that privilege to members" do
      assert @memex.viewer_is_admin?(@admin)
      refute_predicate @org, :members_can_change_project_visibility?
      assert @memex.viewer_can_change_visibility?(@admin)
      assert @memex.async_viewer_can_change_visibility?(@admin).sync
    end

    test "returns true for a project admin when the org grants the necessary privilege to members" do
      @org.allow_members_to_change_project_visibility(actor: @admin)
      @memex.grant_role(@org_member, :admin)

      assert @memex.viewer_is_admin?(@org_member)
      assert_predicate @org, :members_can_change_project_visibility?
      assert @memex.viewer_can_change_visibility?(@org_member)
      assert @memex.async_viewer_can_change_visibility?(@org_member).sync
    end

    test "returns false for a project admin when the org does not grant the necessary privilege to members" do
      @memex.grant_role(@org_member, :admin)

      assert @memex.viewer_is_admin?(@org_member)
      refute_predicate @org, :members_can_change_project_visibility?
      refute @memex.viewer_can_change_visibility?(@org_member)
      refute @memex.async_viewer_can_change_visibility?(@org_member).sync
    end

    test "returns false for an org member who is not a project admin" do
      @org.allow_members_to_change_project_visibility(actor: @admin)

      refute @memex.viewer_is_admin?(@org_member)
      assert_predicate @org, :members_can_change_project_visibility?
      refute @memex.viewer_can_change_visibility?(@org_member)
      refute @memex.async_viewer_can_change_visibility?(@org_member).sync
    end

    test "returns false for a project admin who is not an org member" do
      @org.allow_members_to_change_project_visibility(actor: @admin)
      @memex.grant_role(@non_member, :admin)

      refute @org.member?(@non_member)
      assert @memex.viewer_is_admin?(@non_member)
      assert_predicate @org, :members_can_change_project_visibility?
      refute @memex.viewer_can_change_visibility?(@org_member)
      refute @memex.async_viewer_can_change_visibility?(@org_member).sync
    end

    test "returns true for an org member with greater privileges than org-wide writer default" do
      @org.allow_members_to_change_project_visibility(actor: @admin)
      @memex.update_organization_wide_role("project_writer", @admin)
      @memex.grant_role(@org_member, :admin)

      assert @memex.viewer_is_admin?(@org_member)
      assert_predicate @org, :members_can_change_project_visibility?
      assert @memex.viewer_can_change_visibility?(@org_member)
      assert @memex.async_viewer_can_change_visibility?(@org_member).sync
    end

    test "returns true for the owner of a user-owned project" do
      assert @user_owned_memex.viewer_is_admin?(@user)
      assert @user_owned_memex.viewer_can_change_visibility?(@user)
      assert @user_owned_memex.async_viewer_can_change_visibility?(@user).sync
    end

    test "returns true for a non-owner project admin of a user-owned project" do
      @user_owned_memex.grant_role(@org_member, :admin)

      assert @user_owned_memex.viewer_is_admin?(@org_member)
      assert @user_owned_memex.viewer_can_change_visibility?(@org_member)
      assert @user_owned_memex.async_viewer_can_change_visibility?(@org_member).sync
    end

    test "returns false for a non-admin of a user-owned project" do
      refute @user_owned_memex.viewer_is_admin?(@org_member)
      refute @user_owned_memex.viewer_can_change_visibility?(@org_member)
      refute @user_owned_memex.async_viewer_can_change_visibility?(@org_member).sync
    end
  end

  context "#async_closable_by?" do
    context "user owned projects" do
      test "owner can close the project" do
        assert @user_owned_memex.async_closable_by?(@user).sync
      end

      test "non-owner cannot close the project" do
        refute @user_owned_memex.async_closable_by?(@non_member).sync
      end

      test "write collaborators can close the project" do
        @user_owned_memex.grant_role(@non_member, Role.project_writer_role)
        assert @user_owned_memex.async_closable_by?(@non_member).sync
      end

      test "non-owner cannot close public projects" do
        @user_owned_memex.update!(public: true)
        refute @user_owned_memex.async_closable_by?(@non_member).sync
      end
    end

    context "org owned projects" do
      test "org admin can close the project" do
        assert @memex.async_closable_by?(@org.admins.first).sync
      end

      test "org member cannot close the project if org wide access is set to read" do
        MemexHelpers::setup_organization_wide_access("project_reader", @memex)
        refute @memex.async_closable_by?(@org_member).sync
      end

      test "org member can close the project if org wide access is set to write" do
        MemexHelpers::setup_organization_wide_access("project_writer", @memex)
        assert @memex.async_closable_by?(@org_member).sync
      end

      test "org member cannot close the project if org wide access is set to none" do
        MemexHelpers::setup_organization_wide_access("none", @memex)
        refute @memex.async_closable_by?(@org_member).sync
      end

      test "write collaborators can close the memex" do
        MemexHelpers::setup_organization_wide_access("none", @memex)
        @memex.grant_role(@non_member, Role.project_writer_role)
        assert @memex.async_closable_by?(@non_member).sync
      end

      test "non member cannot close the project" do
        refute @memex.async_closable_by?(@non_member).sync
      end

      test "non member cannot close public projects project" do
        @memex.update!(public: true)
        refute @memex.async_closable_by?(@non_member).sync
      end
    end
  end

  context "#async_reopenable_by?" do
    context "user owned projects" do
      test "owner can close the project" do
        assert @user_owned_memex.async_reopenable_by?(@user).sync
      end

      test "non-owner cannot close the project" do
        refute @user_owned_memex.async_reopenable_by?(@non_member).sync
      end

      test "write collaborators can close the project" do
        @user_owned_memex.grant_role(@non_member, Role.project_writer_role)
        assert @user_owned_memex.async_reopenable_by?(@non_member).sync
      end

      test "non-owner cannot close public projects" do
        @user_owned_memex.update!(public: true)
        refute @user_owned_memex.async_reopenable_by?(@non_member).sync
      end
    end

    context "org owned projects" do
      test "org admin can close the project" do
        assert @memex.async_reopenable_by?(@org.admins.first).sync
      end

      test "org member cannot close the project if org wide access is set to read" do
        MemexHelpers::setup_organization_wide_access("project_reader", @memex)
        refute @memex.async_reopenable_by?(@org_member).sync
      end

      test "org member can close the project if org wide access is set to write" do
        MemexHelpers::setup_organization_wide_access("project_writer", @memex)
        assert @memex.async_reopenable_by?(@org_member).sync
      end

      test "org member cannot close the project if org wide access is set to none" do
        MemexHelpers::setup_organization_wide_access("none", @memex)
        refute @memex.async_reopenable_by?(@org_member).sync
      end

      test "write collaborators can close the memex" do
        MemexHelpers::setup_organization_wide_access("none", @memex)
        @memex.grant_role(@non_member, Role.project_writer_role)
        assert @memex.async_reopenable_by?(@non_member).sync
      end

      test "non member cannot close the project" do
        refute @memex.async_reopenable_by?(@non_member).sync
      end

      test "non member cannot close public projects project" do
        @memex.update!(public: true)
        refute @memex.async_reopenable_by?(@non_member).sync
      end
    end
  end

  context "#view_live_update_authzd_attributes" do
    test "contains a pinned version attribute" do
      assert_equal 5, @memex.view_live_update_authzd_attributes[:version]
    end
  end

  private def fetch_roles_for(project: , actor: , role:)
    UserRole.where(target_type: "MemexProject", target_id: project.id, actor_id: actor.id, role: role)
  end
end
