# typed: true
# frozen_string_literal: true

require "test_helper"

class Permissions::ActorCanWriteRepositoryTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @user_owned_repo = create(:private_repository, :minimal)
    @user_owned_owner = @user_owned_repo.owner
    @rando = create :user
    # Org owned repo fixtures
    @repo = create(:private_repository, :minimal, owner: create(:enterprise_linked_organization))
    @org = @repo.owner
    @org_admin = @org.admins.first
    # Set org base permissions to none to avoid unintended side effects
    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:none, actor: @org_admin) }
    @business = @org.business
    @org_member = create :user
    @org.add_member @org_member, action: :write
    @org_team = create :team, organization: @org, permission: "push"
    @org_team_member = create :user
    @org.add_member @org_team_member, action: :write
    @org_team.add_member @org_team_member
    #
    # helper method enables FF for ETv2
    @all_org_team_member, @all_org_team = add_user_to_enterprise_team(business: @repo.business)
    #
    # These need to be done manually to get the org selection type the way we need
    @select_org_team = create(:business_team, business: @business, organization_selection_type: :selected)
    _business_org_team_assignment = BusinessTeamOrgAssignment.create!(business_team: @select_org_team, organization: @org)
    @select_org_team_member = create :user
    create(:business_user_account, user: @select_org_team_member, business: @business)
    @select_org_team.add_member(@select_org_team_member, caller_type: :business_team)
    #
    @unselected_biz_team = create(:business_team, business: @business, organization_selection_type: :selected)
    @unselected_biz_team_member = create :user
    create(:business_user_account, user: @unselected_biz_team_member, business: @business)

    @unselected_biz_team.add_member(@unselected_biz_team_member, caller_type: :business_team)
    enable_feature_flag(:enterprise_teams_org_roles)
    enable_feature_flag(:enterprise_teams_org_assignment)
  end

  context "User owned repo" do
    test "is writable by owner" do
      assert @user_owned_owner.authorized_for_write? @user_owned_repo
    end

    test "is not writable by a random user" do
      refute @rando.authorized_for_write? @user_owned_repo
    end

    # is writable by a user granted write access
    test "is writable by a user granted write access" do
      @user_owned_repo.add_member(@rando, action: :write)
      assert @rando.authorized_for_write? @user_owned_repo
    end
  end

  context "Org owned repo" do
    test "is not writable prior to grants" do
      refute @org_member.authorized_for_write? @repo
      refute @org_team_member.authorized_for_write? @repo
      refute @all_org_team_member.authorized_for_write? @repo
      refute @select_org_team_member.authorized_for_write? @repo
      refute @unselected_biz_team_member.authorized_for_write? @repo
    end

    test "is writable by a user granted write access" do
      @repo.add_member(@org_member, action: :write)
      assert @org_member.authorized_for_write? @repo
    end

    test "is writable by a user indirectly granted through a team" do
      @org_team.add_repository @repo, :write
      assert @org_team_member.authorized_for_write? @repo
    end

    test "is writable by a user indirectly granted all repo write through a BusinessTeam" do
      enable_feature_flag(:use_associated_org_for_team_role_assignment)
      assert_predicate @org.grant_org_role(assignee: @select_org_team, role: OrganizationRole.all_repo_write_role), :success?
      assert @select_org_team_member.authorized_for_write? @repo
    end

    test "is writable by a user indirectly granted through an enterprise team" do
      @select_org_team.add_repository @repo, :write
      @all_org_team.add_repository @repo, :write
      assert @select_org_team_member.authorized_for_write? @repo
      assert @all_org_team_member.authorized_for_write? @repo
    end

    test "is writable by a user directly granted all repo admin" do
      @org.grant_org_role(assignee: @org_member, role: OrganizationRole.all_repo_write_role)
      assert @org_member.authorized_for_write? @repo
    end

    test "is writable by a user indirectly granted all repo write" do
      assert_predicate @org.grant_org_role(assignee: @org_team, role: OrganizationRole.all_repo_write_role), :success?
      assert @org_team_member.authorized_for_write? @repo
    end

    test "is writable via org base permissions" do
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:write, actor: @org_admin) }
      assert @org_member.authorized_for_write? @repo
      assert @org_team_member.authorized_for_write? @repo
    end

    test "is writable for members of an enterprise team via org base permission" do
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:write, actor: @org_admin) }
      assert @all_org_team_member.authorized_for_write? @repo
      assert @select_org_team_member.authorized_for_write? @repo
      refute @unselected_biz_team_member.authorized_for_write? @repo
    end

    test "is writable by an owner of the owning organization" do
      assert @org_admin.authorized_for_write? @repo
    end
  end

  context "User owned private fork" do
    test "is writable by the owner of the parent of the fork" do
      fork_parent_repo = create(:private_repository, owner: @org)
      fork_parent_repo.allow_private_repository_forking(actor: @org_admin)
      fork_parent_repo.add_member @org_member
      forked_repo = create(:fork_repository, forker: @org_member, fork_repo: fork_parent_repo)
      assert @org_admin.authorized_for_write? forked_repo
    end
  end
end

class User
  def authorized_for_write?(repo)
    ::Permissions::Enforcer.authorize(
      action: :test_macro_actor_can_write_repository,
      actor: self,
      subject: repo
    ).allow?
  end
end
