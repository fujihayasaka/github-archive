# typed: true
# frozen_string_literal: true

require "test_helper"

class PermissionsCustomRolesTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    GitHub.flipper[:custom_enterprise_role_feature].enable
    @ent = create(:business)
    @org = create(:business_plus_organization)
    @admin = @org.admins.first
    @repo = create(:repository, :minimal, owner: @org)

    @members = [create(:user), create(:user)]
    @collaborators = [create(:user), create(:user)]
    @teams = [create(:team, organization: @org), create(:team, organization: @org)]
    @invitation = create(
      :repository_invitation,
      invitee: create(:user),
      inviter: @admin,
      permissions: nil,
      role_id: nil
    )

    @custom_role_name = "developer"
    @custom_repo_role = create(:custom_repository_role, :with_extra_permissions, name: @custom_role_name,
      owner_id: @org.id, owner_type: "Organization", base_role_id: Role.maintain_role.id)
    @custom_org_role = create(:custom_organization_role, owner_id: @org.id)
    @custom_ent_role = create(:custom_enterprise_role, owner_id: @ent.id)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    @org_fgp_a = Permissions::FineGrainedPermissionIm.find(:manage_organization_webhooks)
    @org_fgp_b = Permissions::FineGrainedPermissionIm.find(:read_audit_logs)
    @ent_fgp_a = Permissions::FineGrainedPermissionIm.find(:write_enterprise_custom_org_role)
    @ent_fgp_b = Permissions::FineGrainedPermissionIm.find(:read_enterprise_custom_org_role)
  end

  if GitHub.hydro_enabled?
    test "records a Hydro event when custom repository role successfully created" do
      custom_role = RepositoryRole.new(
        name: "designer",
        owner_id: @org.id,
        owner_type: "Organization",
        base_role: Role.write_role
      )
      Permissions::CustomRoles.create!(custom_role, fgps: [:manage_settings_wiki, :manage_settings_projects])

      assert_hydro_published({
        role: Hydro::EntitySerializer.custom_repository_role(custom_role),
        org_custom_roles_count: 2
      }, schema: "github.custom_repository_roles.v0.CustomRepositoryRoleCreated")
    end

    test "records a Hydro event when custom organization role successfully created" do
      custom_role = OrganizationRole.new(
        name: "designer",
        owner_id: @org.id,
        owner_type: "Organization")
      Permissions::CustomRoles.create!(custom_role, fgps: [@org_fgp_a.action.to_sym])

      assert_hydro_published({
        role: Hydro::EntitySerializer.custom_organization_role(custom_role),
        org_custom_org_roles_count: 2
      }, count: 1, schema: "github.custom_organization_roles.v0.CustomOrganizationRoleCreated")
    end

    test "records a Hydro event when custom enterprise role successfully created" do
      GitHub.flipper[:custom_enterprise_role_feature].enable
      custom_role = EnterpriseRole.new(
        name: "designer",
        owner_id: @ent.id,
        owner_type: "Business")
      Permissions::CustomRoles.create!(custom_role, fgps: [@ent_fgp_a.action.to_sym])

      assert_hydro_published({
        role: Hydro::EntitySerializer.custom_enterprise_role(custom_role),
        enterprise_custom_roles_count: 2
      }, count: 1, schema: "github.custom_enterprise_roles.v0.CustomEnterpriseRoleCreated")
    end

    test "does not record a Hydro event if custom role wasn't created successfully" do
      # can't create a custom role with the [reserved] name `Admin`
      custom_role = RepositoryRole.new(
        name: "Admin",
        owner_id: @org.id,
        owner_type: "Organization",
        base_role: Role.write_role
      )
      assert_raises Role::CustomRoleError do
        Permissions::CustomRoles.create!(custom_role, fgps: [:manage_settings_wiki, :manage_settings_projects])
      end
      refute custom_role.valid?
      refute custom_role.persisted?

      assert_hydro_messages(count: 0, schema: "github.custom_repository_roles.v0.CustomRepositoryRoleCreated")
    end
  end

  context "CustomRoles.destroy" do
    test "successfully deletes role after dependent org members permission to repo have been updated" do
      @members.each do |member|
        @org.add_member(member)
        @repo.add_member(member, action: @custom_role_name)
      end
      expected_results = %w[maintain maintain]

      GitHub.dogstats.expects(:gauge).with("orgs_roles.delete.count", 2, tags: ["member_type:member"]).once
      only = [BatchUpdateMemberRepoPermissionsJob]
      perform_enqueued_jobs(only: only) do
        Permissions::CustomRoles.destroy!(@custom_repo_role, @admin)
      end
      @members.map(&:reload)
      actual_results = @members.map { |member| @repo.direct_role_for(member).to_s }

      assert_equal 1, GitHub.dogstats.increments("orgs_roles.delete.queued_to_delete", tags: ["status:queued"]).length
      assert_equal 1, GitHub.dogstats.increments("orgs_roles.delete.queued_to_delete", tags: ["status:deleted"]).length
      assert_same_elements expected_results, actual_results
      assert_nil RepositoryRole.custom_role_by_name(@custom_role_name, owner: @org)
    end

    test "successfully deletes role after dependent org collaborators permission to repo have been updated" do
      @collaborators.each do |collaborator|
        @repo.add_member(collaborator, action: @custom_role_name)
      end
      expected_results = %w[maintain maintain]

      GitHub.dogstats.expects(:gauge).with("orgs_roles.delete.count", 2, tags: ["member_type:member"]).once
      only = [BatchUpdateMemberRepoPermissionsJob]
      perform_enqueued_jobs(only: only) do
        Permissions::CustomRoles.destroy!(@custom_repo_role, @admin)
      end
      @collaborators.map(&:reload)
      actual_results = @collaborators.map { |collaborator| @repo.direct_role_for(collaborator).to_s }

      assert_equal 1, GitHub.dogstats.increments("orgs_roles.delete.queued_to_delete", tags: ["status:queued"]).length
      assert_equal 1, GitHub.dogstats.increments("orgs_roles.delete.queued_to_delete", tags: ["status:deleted"]).length
      assert_same_elements expected_results, actual_results
      assert_nil RepositoryRole.custom_role_by_name(@custom_role_name, owner: @org)
    end

    test "successfully deletes role after dependent team permissions to repo have been updated" do
      @teams.each do |team|
        team.add_repository @repo, @custom_repo_role.name
      end
      expected_results = %w[maintain maintain]

      GitHub.dogstats.expects(:gauge).with("orgs_roles.delete.count", 2, tags: ["member_type:team"]).once
      only = [BatchUpdateTeamRepoPermissionsJob]
      perform_enqueued_jobs(only: only) do
        Permissions::CustomRoles.destroy!(@custom_repo_role, @admin)
      end
      @teams.map(&:reload)
      actual_results = @teams.map { |team| @repo.direct_role_for(team).to_s }

      assert_equal 1, GitHub.dogstats.increments("orgs_roles.delete.queued_to_delete", tags: ["status:queued"]).length
      assert_equal 1, GitHub.dogstats.increments("orgs_roles.delete.queued_to_delete", tags: ["status:deleted"]).length
      assert_same_elements expected_results, actual_results
      assert_nil RepositoryRole.custom_role_by_name(@custom_role_name, owner: @org)
    end

    test "successfully deletes role after dependent repo invitations to repo have been updated" do
      @invitation.update(repository: @repo, role_id: @custom_repo_role.id)
      assert_equal @custom_role_name, @invitation.reload.permission_string

      GitHub.dogstats.expects(:gauge).with("orgs_roles.delete.count", 1, tags: ["member_type:invitee"]).once
      only = [BatchUpdateInvitationRepoPermissionsJob]
      perform_enqueued_jobs(only: only) do
        Permissions::CustomRoles.destroy!(@custom_repo_role, @admin)
      end
      @invitation.reload

      assert_equal 1, GitHub.dogstats.increments("orgs_roles.delete.queued_to_delete", tags: ["status:queued"]).length
      assert_equal 1, GitHub.dogstats.increments("orgs_roles.delete.queued_to_delete", tags: ["status:deleted"]).length
      assert_equal "maintain", @invitation.reload.permission_string
      assert_nil RepositoryRole.custom_role_by_name(@custom_role_name, owner: @org)
    end

    test "deletes role after team associations removed (organization role)" do
      org_role_name = @custom_org_role.name
      @teams.each do |team|
        # todo - use higher level calls when available
        Permissions::Granters::RoleGranter.new(actor: team, target: @org, role: @custom_org_role, grantor: @admin).grant!
        assert UserRole.where(actor_id: team.id, actor_type: "Team", target_id: @org.id, target_type: "Organization", role_id: @custom_org_role.id).any?
      end

      Permissions::CustomRoles.destroy!(@custom_org_role, @admin)
      @members.map(&:reload)
      # todo - use higher level calls when available
      assigned_org_roles = UserRole.where(actor_id: @members.map(&:id), actor_type: "User", target_id: @org.id, target_type: "Organization", role_id: @custom_org_role.id)

      assert_empty assigned_org_roles
      assert_nil OrganizationRole.custom_role_by_name(org_role_name, owner: @org)
    end

    test "deletes role after user associations removed (organization role)" do
      org_role_name = @custom_org_role.name
      @members.each do |member|
        @org.add_member(member)
        # todo - use higher level calls when available
        Permissions::Granters::RoleGranter.new(actor: member, target: @org, role: @custom_org_role, grantor: @admin).grant!
        assert UserRole.where(actor_id: member.id, actor_type: "User", target_id: @org.id, target_type: "Organization", role_id: @custom_org_role.id).any?
      end

      Permissions::CustomRoles.destroy!(@custom_org_role, @admin)
      @members.map(&:reload)
      # todo - use higher level calls when available
      assigned_org_roles = UserRole.where(actor_id: @members.map(&:id), actor_type: "User", target_id: @org.id, target_type: "Organization", role_id: @custom_org_role.id)

      assert_empty assigned_org_roles
      assert_nil OrganizationRole.custom_role_by_name(org_role_name, owner: @org)
    end

    test "deletes role and removes team associations (enterprise role)" do
      GitHub.flipper[:custom_enterprise_role_feature].enable
      ent_role_name = @custom_ent_role.name
      @ent.add_user_accounts(@members)
      @teams.each do |team|
        # todo - use higher level calls when available
        Permissions::Granters::RoleGranter.new(actor: team, target: @ent, role: @custom_ent_role, grantor: @ent.owners.first).grant!
        assert UserRole.where(actor_id: team.id, actor_type: "Team", target_id: @ent.id, target_type: "Business", role_id: @custom_ent_role.id).any?
      end

      Permissions::CustomRoles.destroy!(@custom_ent_role, @ent.owners.first)
      @teams.map(&:reload)
      # todo - use higher level calls when available
      assigned_ent_roles = UserRole.where(actor_id: @teams.map(&:id), actor_type: "Team", target_id: @ent.id, target_type: "Business", role_id: @custom_ent_role.id)

      assert_empty assigned_ent_roles
      assert_nil EnterpriseRole.custom_role_by_name(ent_role_name, owner: @ent)
    end

    test "deletes role and removes user associations (enterprise role)" do
      GitHub.flipper[:custom_enterprise_role_feature].enable
      ent_role_name = @custom_ent_role.name
      @ent.add_user_accounts(@members)
      @members.each do |member|
        # todo - use higher level calls when available
        Permissions::Granters::RoleGranter.new(actor: member, target: @ent, role: @custom_ent_role, grantor: @ent.owners.first).grant!
        assert UserRole.where(actor_id: member.id, actor_type: "User", target_id: @ent.id, target_type: "Business", role_id: @custom_ent_role.id).any?
      end

      Permissions::CustomRoles.destroy!(@custom_ent_role, @ent.owners.first)
      @members.map(&:reload)
      # todo - use higher level calls when available
      assigned_ent_roles = UserRole.where(actor_id: @members.map(&:id), actor_type: "User", target_id: @ent.id, target_type: "Business", role_id: @custom_ent_role.id)

      assert_empty assigned_ent_roles
      assert_nil EnterpriseRole.custom_role_by_name(ent_role_name, owner: @ent)
    end

    test "clears permission cache" do
      PermissionCache.enable do
        PermissionCache.set("key", "value")
        assert_equal "value", PermissionCache.get("key")
        Permissions::CustomRoles.destroy!(@custom_org_role, fgps: [])
        assert_nil PermissionCache.get("key")
      end
    end
  end

  context "CustomRoles#create" do
    test "persists a custom repository role with provided FGPs" do
      custom_role = RepositoryRole.new(
        name: "repo_custom_role",
        owner_id: @org.id,
        owner_type: "Organization",
        base_role: Role.write_role
      )
      Permissions::CustomRoles.create!(custom_role, fgps: [:manage_settings_wiki, :manage_settings_projects])
      assert custom_role.persisted?
      assert custom_role.valid?
    end

    test "persists a custom organization role with provided FGPs" do
      custom_role = OrganizationRole.new(
        name: "org_custom_role",
        owner_id: @org.id,
        owner_type: "Organization"
      )
      Permissions::CustomRoles.create!(custom_role, fgps: [@org_fgp_a.action.to_sym])
      assert custom_role.persisted?
      assert custom_role.valid?
    end

    test "does not include disabled FGPs" do
      custom_role = RepositoryRole.new(
        name: "repo_custom_role",
        owner_id: @org.id,
        owner_type: "Organization",
        base_role: Role.read_role
      )

      Permissions::CustomRoles.create!(custom_role, fgps: [:remove_label])

      assert custom_role.persisted?
      assert custom_role.valid?
      refute_includes custom_role.permissions.map(&:action), "remove_label"
    end

    test "raises when FGP target type does not match role target type" do
      custom_role = RepositoryRole.new(
        name: "repo custom role",
        owner_id: @org.id,
        owner_type: "Organization",
        base_role: Role.write_role
      )

      assert_raises Role::CustomRoleError do
        Permissions::CustomRoles.create!(custom_role, fgps: [@org_fgp_a.action.to_sym])
      end
      refute custom_role.persisted?
    end

    test "raises when role has unsupported target type'" do
      package_role = Role.new(
        name: "package role",
        target_type: "Package",
        owner_id: @org.id,
        owner_type: "Organization",
        base_role: Role.write_role
      )

      assert_raises Role::CustomRoleError do
        Permissions::CustomRoles.create!(package_role, fgps: [])
      end
      refute package_role.persisted?
    end

    test "raises when role has nil target type" do
      typeless_role = Role.new(
        name: "typeless role",
        target_type: nil,
        owner_id: @org.id,
        owner_type: "Organization",
        base_role: Role.write_role
      )

      assert_raises Role::CustomRoleError do
        Permissions::CustomRoles.create!(typeless_role, fgps: [])
      end
      refute typeless_role.persisted?
    end

    test "raises when role is EnterpriseRole but FF is disabled" do
      GitHub.flipper[:custom_enterprise_role_feature].disable
      role = EnterpriseRole.new(
        name: "test role",
        target_type: "Business",
        owner_id: @ent.id,
        owner_type: "Business",
        base_role: Role.write_role
      )

      assert_raises Role::CustomRoleError do
        Permissions::CustomRoles.create!(role, fgps: [])
      end
      refute role.persisted?
    end

    test "org roles can have repo and org FGPs" do
      all_repo_role = Role.new(
        name: "all repo role",
        target_type: "Organization",
        owner_id: @org.id,
        owner_type: "Organization",
        base_role: Role.write_role)

      repo_fgp = :manage_settings_wiki
      org_fgp = :manage_organization_webhooks

      Permissions::CustomRoles.create!(all_repo_role, fgps: [repo_fgp, org_fgp])

      assert_same_elements [repo_fgp.to_s, org_fgp.to_s], all_repo_role.permissions.map(&:action).sort
    end

    test "org role must have a base role if it has repo fgps" do
      org_role = Role.new(
        name: "all repo role",
        target_type: "Organization",
        owner_id: @org.id,
        owner_type: "Organization")

      assert_raises Role::CustomRoleError do
        Permissions::CustomRoles.create!(org_role, fgps: [:manage_settings_wiki])
      end
    end

    test "clears permission cache" do
      custom_role = OrganizationRole.new(
        name: "org_custom_role",
        owner_id: @org.id,
        owner_type: "Organization"
      )
      PermissionCache.enable do
        PermissionCache.set("key", "value")
        assert_equal "value", PermissionCache.get("key")
        Permissions::CustomRoles.create!(custom_role, fgps: [])
        assert_nil PermissionCache.get("key")
      end
    end
  end

  context "CustomRoles#update" do
    test "updates a custom repository role with provided FGPs" do
      Permissions::CustomRoles.update!(@custom_repo_role, role_params: {}, fgps: [:manage_settings_wiki, :manage_settings_projects])

      assert @custom_repo_role.persisted?
      assert @custom_repo_role.valid?

      updated_permissions = @custom_repo_role.permissions.map(&:action)
      assert_includes updated_permissions, "manage_settings_wiki"
      assert_includes updated_permissions, "manage_settings_projects"
    end

    test "updates a custom organization role with provided FGPs" do
      Permissions::CustomRoles.update!(@custom_org_role, role_params: {}, fgps: [@org_fgp_a.action.to_sym, @org_fgp_b.action.to_sym])

      assert @custom_org_role.persisted?
      assert @custom_org_role.valid?

      updated_permissions = @custom_org_role.permissions.map(&:action)
      assert_equal 2, updated_permissions.count
      assert_includes updated_permissions, @org_fgp_a.action.to_s
      assert_includes updated_permissions, @org_fgp_b.action.to_s
    end

    test "does not add a disabled FGP" do
      custom_role = create(:custom_repository_role, name: "custom_read_role",
        owner_id: @org.id, owner_type: "Organization", base_role_id: Role.read_role.id)
      Permissions::CustomRoles.update!(custom_role, role_params: {}, fgps: [:remove_label])
      assert custom_role.persisted?
      assert custom_role.valid?
      refute_includes custom_role.permissions.map(&:action), "remove_label"
    end

    test "raises when FGP target type does not match role target type" do
      assert_raises Role::CustomRoleError do
        Permissions::CustomRoles.update!(@custom_repo_role, role_params: {}, fgps: [@org_fgp_a.action.to_sym])
      end
      refute_includes @custom_repo_role.permissions.map(&:action), @org_fgp_a.action
    end

    test "raises when changing a role to an unsupported target type" do
      assert_raises Role::CustomRoleError do
        Permissions::CustomRoles.update!(@custom_repo_role, role_params: { target_type: "Package" }, fgps: [])
      end
      assert_equal "Repository", @custom_repo_role.reload.target_type
    end

    test "raises when role has unsupported target type" do
      original_name = "package role"
      package_role = Role.create!(
        name: original_name,
        target_type: "Package",
        owner_id: @org.id,
        owner_type: "Organization",
        base_role_id: Role.read_role.id)

      assert_raises Role::CustomRoleError do
        Permissions::CustomRoles.update!(package_role, role_params: { name: original_name + "_but_better" }, fgps: [])
      end
      assert_equal original_name, package_role.reload.name
    end

    test "raises when role is EnterpriseRole but FF is disabled" do
      original_name = "first role"
      role = EnterpriseRole.create!(
        name: original_name,
        target_type: "Business",
        owner_id: @ent.id,
        owner_type: "Business",
        base_role: Role.write_role
      )

      GitHub.flipper[:custom_enterprise_role_feature].disable
      role.reload # needed to un-cache FF

      assert_raises Role::CustomRoleError do
        Permissions::CustomRoles.update!(role, role_params: { name: original_name + "_but_better" }, fgps: [])
      end
      assert_equal original_name, role.reload.name
    end

    test "raises when removing a base role from an org role with repo fgps" do
      all_repo_role = OrganizationRole.new(
        name: "all repo role",
        owner_id: @org.id,
        owner_type: "Organization",
        base_role_id: Role.read_role.id)
      Permissions::CustomRoles.create!(all_repo_role, fgps: [:manage_settings_wiki])

      assert_raises Role::CustomRoleError do
        Permissions::CustomRoles.update!(all_repo_role, role_params: { base_role_id: nil }, fgps: [:manage_settings_wiki])
      end
    end

    test "supports removing a base role and all repo fgps from an org role" do
      all_repo_role = OrganizationRole.new(
        name: "all repo role",
        owner_id: @org.id,
        owner_type: "Organization",
        base_role_id: Role.read_role.id)
      Permissions::CustomRoles.create!(all_repo_role, fgps: [:manage_settings_wiki])

      Permissions::CustomRoles.update!(all_repo_role, role_params: { base_role_id: nil }, fgps: [])
      all_repo_role.reload
      assert_nil all_repo_role.base_role
      assert_empty all_repo_role.permissions
    end

    test "clears permission cache even when no changes to role" do
      PermissionCache.enable do
        PermissionCache.set("key", "value")
        assert_equal "value", PermissionCache.get("key")
        Permissions::CustomRoles.update!(@custom_org_role, role_params: {}, fgps: @custom_org_role.permissions.map(&:action).map(&:to_sym))
        assert_nil PermissionCache.get("key")
      end
    end
  end

  context "CustomRoles#udpate_users" do
    test "throws for Organization roles" do
      assert_raises Role::CustomRoleError do
        Permissions::CustomRoles.update_users(@custom_org_role, actor: create(:user))
      end
    end
  end
end
