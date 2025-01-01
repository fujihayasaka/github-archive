# typed: false
# frozen_string_literal: true

require "test_helper"

module OrganizationOwnedRepoSharedTests
  extend ActiveSupport::Concern

  included do
    test "in_organization" do
      assert @repo.in_organization?
    end

    test "emu_org_owned" do
      assert_equal @org1.enterprise_managed_user_enabled?, @repo.emu_org_owned?
    end

    test "emu_user_owned" do
      refute @repo.emu_user_owned?
    end

    test "async_is_owner_enterprise_managed_organization" do
      assert_equal @org1.enterprise_managed_user_enabled?, @repo.async_is_owner_enterprise_managed_organization?.sync
    end
  end
end

module UserOwnedRepoSharedTests
  extend ActiveSupport::Concern

  included do
    test "in_organization", skip_with_all_emus: true do
      refute @repo.in_organization?
    end

    test "emu_org_owned", skip_with_all_emus: true do
      refute @repo.emu_org_owned?
    end

    test "emu_user_owned", skip_with_all_emus: true do
      assert_equal @owner.is_enterprise_managed?, @repo.emu_user_owned?
    end

    test "async_is_owner_enterprise_managed_organization", skip_with_all_emus: true do
      assert_equal false, @repo.async_is_owner_enterprise_managed_organization?.sync
    end
  end
end


require "test_helpers/api_programmatic_grant_helpers"

class RepositoryOrganizationsDependencyTest < GitHub::TestCase
  include OrganizationOwnedRepoSharedTests
  include ApiProgrammaticGrantHelpers
  include GitHub::AssertionTestHelpers

  fixtures do
    @defunkt  = create(:user, login: "defunkt",  plan: "medium")
    @mojombo  = create(:user, login: "mojombo2", plan: "medium")
    @pj       = create(:user, login: "pj",       plan: "medium")
    @org1 = create(:organization, plan: "bronze")
    @org1_owners_team = @org1.legacy_owners_team
    @org2 = create(:organization)
    @owner = @org1.admins.first
    @org1.allow_private_repository_forking(actor: @owner, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
    @org2.add_admin(@owner)
    @repo = create(:private_repository, owner: @org1, from_example: :simple)
    @fork = create(:fork_repository, forker: @owner, fork_repo: @repo, organization: @org2)
    @pub_repo = create(:repository, owner: @org1, from_example: :simple)
    @pub_fork = create(:fork_repository, forker: @owner, fork_repo: @pub_repo, organization: @org2)
    @team = create(:team, organization: @org1, permission: "pull")
    @user = create(:user)
    @team.add_member @user
    assert @team.add_repository(@repo, :pull).success?
    @grit     = create(:repository, name: "grit",     owner: @mojombo)
    @ambition = create(:private_repository, name: "ambition", owner: @defunkt)

    @business_org = create :business_plus_organization
    @business_org_repo = create :private_repository, owner: @business_org, from_example: :simple

    @simple   = create(:repository, name: "simple",   owner: @defunkt)
  end

  test "forking into an org by a non-admin member doesn't add the repo to any teams" do
    @org1.allow_members_can_create_repositories(actor: @owner)

    direct_member = create(:user, login: "direct-member")
    @org1.add_member(direct_member)

    repo = create(:repository)
    repo.add_member(direct_member)

    fork = create(:fork_repository, forker: direct_member, fork_repo: repo, organization: @org1)

    assert fork.adminable_by?(direct_member)
    assert_empty fork.teams
  end

  # This is to mirror Organization#repositories, which was the prior behavior.
  test "a user-owned fork is not added to its organization's owners team" do
    user_fork = create(:fork_repository, forker: @owner, fork_repo: @repo)
    refute_able @org1_owners_team, :admin, user_fork
  end

  test "a user-owned fork is added to the same teams its parent is on if the forker is a team member" do
    only = [RepositoryAddTeamsJob]
    user_fork = perform_enqueued_jobs(only: only) { create(:fork_repository, forker: @user, fork_repo: @repo) }
    assert_able @team, :read, user_fork
  end

  test "a user-owned fork is added to the same teams with the same perms as its parent if the forker is an org member" do
    member = create :user, plan: "micro"
    @org1.add_admin member
    only = [RepositoryAddTeamsJob]
    user_fork = perform_enqueued_jobs(only: only) { create(:fork_repository, forker: member, fork_repo: @repo) }
    assert_able @team, :read, user_fork
    refute_able @team, :write, user_fork
  end

  test "a repo is not added to its organization's owners team" do
    repo = create(:repository, owner: @org1)
    refute_able @org1_owners_team, :admin, repo
  end

  test "teams_for includes teams in the repo's organization" do
    assert_includes @repo.teams_for(@user), @team
  end

  context "teams" do
    test "returns nothing for user-owned root repos" do
      assert_equal [], create(:repository).teams
    end

    test "returns only non-owners teams for an organization" do
      assert_equal [@team], @repo.teams
    end

    test "returns teams without inheriting descendants by default" do
      parent_team = create :team, organization: @org1, name: "parent", privacy: :closed
      child_team  = create :team, organization: @org1, name: "child", privacy: :closed, parent_team_id: parent_team.id

      repo = create(:repository, owner: @org1)
      parent_team.add_repository repo, :pull

      assert_same_elements [parent_team], repo.teams
    end

    test "returns teams with inheriting descendants" do
      parent_team = create :team, organization: @org1, name: "parent", privacy: :closed
      child_team  = create :team, organization: @org1, name: "child", privacy: :closed, parent_team_id: parent_team.id

      repo = create(:repository, owner: @org1)
      parent_team.add_repository repo, :pull

      assert_same_elements [parent_team, child_team], repo.teams(immediate_only: false)
    end

    test "includes all repo role teams when specified" do
      team1 = create :team, organization: @business_org, privacy: :closed
      team1.add_repository(@business_org_repo, :write)

      all_repo_team = create :team, organization: @business_org, privacy: :closed
      assert @business_org.grant_org_role(assignee: all_repo_team, role: OrganizationRole.all_repo_write_role).success?

      assert_same_elements [team1, all_repo_team], @business_org_repo.teams(immediate_only: false, include_all_repo_roles: true)
    end

    test "defaults to not include all repo role teams" do
      team1 = create :team, organization: @business_org
      team1.add_repository(@business_org_repo, :write)

      all_repo_team = create :team, organization: @business_org
      assert @business_org.grant_org_role(assignee: all_repo_team, role: OrganizationRole.all_repo_write_role).success?

      assert_same_elements [team1], @business_org_repo.teams(immediate_only: false)
    end
  end

  context "async_teams" do
    test "returns teams without inheriting descendants by default" do
      parent_team = create :team, organization: @org1, name: "parent", privacy: :closed
      child_team  = create :team, organization: @org1, name: "child", privacy: :closed, parent_team_id: parent_team.id

      repo = create(:repository, owner: @org1)
      parent_team.add_repository repo, :pull

      assert_same_elements [parent_team], repo.async_teams.sync
    end

    test "returns teams with inheriting descendants" do
      parent_team = create :team, organization: @org1, name: "parent", privacy: :closed
      child_team  = create :team, organization: @org1, name: "child", privacy: :closed, parent_team_id: parent_team.id

      repo = create(:repository, owner: @org1)
      parent_team.add_repository repo, :pull

      assert_same_elements [parent_team, child_team], repo.async_teams(immediate_only: false).sync
    end
  end

  test "admin_ids is empty when there is no owner", skip_with_all_emus: true do
    repo = create(:repository)
    repo.owner = nil
    assert_empty repo.admin_ids
  end

  test "admin_ids has the org's admins for an org-owned repo" do
    assert_equal [@owner.id], @repo.admin_ids
  end

  test "admin_ids includes admin team members for an org-owned repo" do
    team = create :team, organization: @org1, permission: "admin"
    user = create(:user)
    assert team.add_repository(@repo, :admin).success?
    assert team.add_member(user).success?

    assert_same_elements [@owner.id, user.id], @repo.admin_ids
  end

  test "admin_ids does not include non-admin team members" do
    team = create :team, organization: @org1, permission: "pull"
    user = create(:user)
    assert team.add_repository(@repo, :pull).success?
    assert team.add_member(user).success?

    assert_equal [@owner.id], @repo.admin_ids
  end

  test "admin_ids is the repo's owner for a non-org repo", skip_with_all_emus: true do
    repo = create(:repository)
    assert_equal [repo.owner_id], repo.admin_ids
  end

  test "admin_ids is the owning org's admins for an org-owned fork of a private org repo" do
    assert_same_elements @org2.admin_ids, @fork.admin_ids
  end

  test "admin_ids is just the new owner for a fork of a public org repo", skip_with_all_emus: true do
    user = create(:user)
    forked = create(:fork_repository, forker: user, fork_repo: @pub_repo)
    assert_equal [user.id], forked.admin_ids
  end

  context "updating a repo's organization" do
    test "sets it to the owner if the owner is an organization and repo is a private root" do
      @repo.update organization_id: nil
      @org1.dependent_removed @repo
      assert_nil @repo.reload.organization

      @repo.update_organization

      assert_equal @org1, @repo.organization
      assert_includes @org1.dependents, @repo
    end

    test "sets it to the owner if the owner is an organization and repo is a public root" do
      @pub_repo.update organization_id: nil
      @org1.dependent_removed @pub_repo
      assert_nil @pub_repo.reload.organization

      @pub_repo.update_organization

      assert_equal @org1, @pub_repo.organization
      assert_includes @org1.dependents, @pub_repo
    end

    test "sets it to the parent's organization if the repo is a private, user-owned fork" do
      user_fork = create(:fork_repository, forker: @user, fork_repo: @repo)
      user_fork.update organization_id: nil
      @org1.dependent_removed user_fork
      assert_nil user_fork.reload.organization

      user_fork.update_organization

      assert_equal @org1, user_fork.organization
      assert_includes @org1.dependents, user_fork
    end

    test "sets it to the owner if the repo is a private, org-owned fork" do
      @fork.update organization_id: nil
      @org2.dependent_removed @fork
      assert_nil @fork.reload.organization

      @fork.update_organization

      assert_equal @org2, @fork.organization
      assert_includes @org2.dependents, @fork
    end

    test "sets it to nil if the repo is a public, user-owned fork", skip_with_all_emus: true do
      user_fork = create(:fork_repository, forker: @user, fork_repo: @pub_repo)

      dummy_org = create :organization
      unused_org_id = dummy_org.id
      dummy_org.destroy!

      user_fork.update organization_id: unused_org_id
      @org1.dependent_removed @pub_repo
      assert_nil user_fork.reload.organization

      user_fork.update_organization

      assert_nil user_fork.organization
    end

    test "sets it to the owner if the repo is a public, org-owned fork" do
      dummy_org = create :organization
      unused_org_id = dummy_org.id
      dummy_org.destroy!

      @pub_fork.update organization_id: unused_org_id
      @org2.dependent_removed @pub_fork
      assert_nil @pub_fork.reload.organization

      @pub_fork.update_organization

      assert_equal @org2, @pub_fork.organization
      assert_includes @org2.dependents, @pub_fork
    end

    test "removes the repo as a dependent from the old organization and adds it to the new one" do
      new_org = create(:organization)

      @pub_fork.update owner_id: new_org.id
      assert_equal @org2, @pub_fork.reload.organization

      @pub_fork.update_organization
      assert_equal new_org, @pub_fork.organization
      refute_includes @org2.dependents, @pub_fork
      assert_includes new_org.dependents, @pub_fork
    end

    test "removes the repo's collaborators if it went from user-owned -> org-owned" do
      org = create(:organization)
      repo = create(:repository)
      collab = create(:user)
      collab2 = create(:user)
      repo.add_member collab
      repo.add_member collab2

      repo.update owner_id: org.id
      repo.reload.update_organization
      refute repo.member?(collab)
      refute repo.member?(collab2)
    end

    test "doesn't remove collaborators when instructed not to", skip_with_all_emus: true do
      org = create(:organization)
      repo = create(:repository)
      collab = create(:collaborator, repository: repo)

      repo.update owner_id: org.id
      repo.reload.update_organization remove_collaborators: false
      assert repo.member?(collab)
    end

    test "removes the repo from the teams on the old organization" do
      new_org = create(:organization)
      team = create(:team, organization: @org2, permission: "push")
      team.add_repository @pub_fork, :push

      @pub_fork.update owner_id: new_org.id
      assert_equal @org2, @pub_fork.reload.organization

      @pub_fork.update_organization
      assert_equal new_org, @pub_fork.organization
      refute_includes @org2.dependents, @pub_fork
      refute_includes team.batched_repositories, @pub_fork
      assert_includes new_org.dependents, @pub_fork
    end

    test "doesn't remove and re-add the repo as dependent when the organization doesn't change" do
      new_org = create(:organization)

      @pub_fork.update owner_id: new_org.id
      assert_equal @org2, @pub_fork.reload.organization

      @pub_fork.update_organization
      Organization.any_instance.stubs(:dependent_removed).raises
      Organization.any_instance.stubs(:dependent_added).raises
      @pub_fork.update_organization
    end
  end

  context "add_organization" do
    test "doesn't include the organization in the members list" do
      @repo.add_organization(@org1, action: :read)

      refute_includes @repo.members, @org1
    end

    test "errors when a user is passed" do
      assert_raises ArgumentError do
        @repo.add_organization(@user, action: :read)
      end
    end

    test "errors when nil is passed" do
      assert_raises ArgumentError do
        @repo.add_organization(nil, action: :read)
      end
    end
  end

  context "remove_organization" do
    test "revokes the default repository permission for all organization members", skip_with_all_emus: true do
      @repo.add_organization(@org1, action: :read)

      member = create(:user, login: "org-member")
      @org1.add_member(member)

      assert @repo.pullable_by?(member)

      @repo.remove_organization(@org1)

      refute @repo.pullable_by?(member)
    end

    test "errors when a user is passed" do
      assert_raises ArgumentError do
        @repo.remove_organization(@user)
      end
    end

    test "errors when nil is passed" do
      assert_raises ArgumentError do
        @repo.remove_organization(nil)
      end
    end
  end

  context "pullable_by" do
    test "is false for non-members", skip_with_all_emus: true do
      user = create(:user)
      refute @repo.pullable_by?(user)
    end

    test "is false for anonymous users and private repositories" do
      refute @repo.pullable_by?(nil)
    end

    test "is true for anonymous users and public repositories", skip_with_all_emus: true do
      repo = create(:repository, owner: @org1)
      assert repo.pullable_by?(nil)
    end
  end

  context "actor_ids_for_teams_on_repo" do

    test "includes teams on repo" do
      assert_equal [@team.id],  @repo.actor_ids_for_team_on_repo
    end

    test "includes business teams on repo when enterprise_teams ff is on" do
      business = create(:business)
      enable_feature_flag(:enterprise_teams_crud, business)
      enable_feature_flag(:enterprise_teams_org_assignment, business)
      user = create(:user)
      org = create(:organization, admin: user, business: business)
      repo = create :private_repository, owner: org, from_example: :simple
      team1 = create :team, organization: org
      team1.add_repository(repo, :read)
      team2 = create :team, organization: org
      team2.add_repository(repo, :read)

      business_team = create(:business_team, business: business, organization_selection_type: :all)
      business_team.add_repository(repo, :read)

      team_ids = repo.actor_ids_for_team_on_repo

      assert_equal [business_team.id, team1.id, team2.id], team_ids
    end

    test "does not include business teams on repo when business_team ff is off" do
      enable_feature_flag(:enterprise_teams_crud)
      business = create(:business)
      user = create(:user)
      org = create(:organization, admin: user, business: business)
      repo = create :private_repository, owner: org, from_example: :simple
      team1 = create :team, organization: org
      team1.add_repository(repo, :read)
      team2 = create :team, organization: org
      team2.add_repository(repo, :read)

      business_team = create(:business_team, business: business, organization_selection_type: :all)
      business_team.add_repository(repo, :read)

      disable_feature_flag(:enterprise_teams_crud)
      team_ids = repo.actor_ids_for_team_on_repo

      assert_equal [team1.id, team2.id], team_ids
    end

    test "filter based on actor_ids" do
      team1 = create :team, organization: @business_org
      team1.add_repository(@business_org_repo, :read)
      team2 = create :team, organization: @business_org
      team2.add_repository(@business_org_repo, :read)

      team_ids = @business_org_repo.actor_ids_for_team_on_repo(actor_ids: [team2.id])
      refute_includes team_ids, team1.id
      assert_equal [team2.id], team_ids
    end

    test "filter based on action or role" do
      team_read = create :team, organization: @business_org
      team_read.add_repository(@business_org_repo, :pull)
      team_triage = create :team, organization: @business_org
      team_triage.add_repository(@business_org_repo, :triage)
      team_admin = create :team, organization: @business_org
      team_admin.add_repository(@business_org_repo, :admin)

      read_team_ids = @business_org_repo.actor_ids_for_team_on_repo(action: :read)
      refute_includes read_team_ids, team_triage.id
      refute_includes read_team_ids, team_admin.id
      assert_equal [team_read.id], read_team_ids

      triage_team_ids = @business_org_repo.actor_ids_for_team_on_repo(action: :triage)
      refute_includes triage_team_ids, team_read.id
      refute_includes triage_team_ids, team_admin.id
      assert_equal [team_triage.id], triage_team_ids

      admin_team_ids = @business_org_repo.actor_ids_for_team_on_repo(action: :admin)
      refute_includes admin_team_ids, team_read.id
      refute_includes admin_team_ids, team_triage.id
      assert_equal [team_admin.id], admin_team_ids
    end

    test "filter out custom repo role assignments that have the requested role as base role" do
      team_read = create :team, organization: @business_org
      team_read.add_repository(@business_org_repo, :pull)
      team_custom = create :team, organization: @business_org
      custom_role = create(:role, :with_extra_permissions, owner_id: @business_org.id, owner_type: "Organization", base_role_id: Role.read_role.id)

      team_custom.add_repository(@business_org_repo, custom_role.name)

      read_role_team_ids = @business_org_repo.actor_ids_for_team_on_repo(action: :read)

      assert_same_elements read_role_team_ids, [team_read.id]
      refute_includes read_role_team_ids, team_custom.id
    end

    test "filter based on min_action" do
      team_write = create :team, organization: @business_org
      team_write.add_repository(@business_org_repo, :push)
      team_admin = create :team, organization: @business_org
      team_admin.add_repository(@business_org_repo, :admin)

      read_or_higher_team_ids = @business_org_repo.actor_ids_for_team_on_repo(min_action: :read)
      assert_same_elements [team_write.id, team_admin.id], read_or_higher_team_ids

      admin_team_ids = @business_org_repo.actor_ids_for_team_on_repo(min_action: :admin)
      assert_same_elements [team_admin.id], admin_team_ids
    end

    test "filter based on action and actor_ids" do
      team1 = create :team, organization: @business_org
      team1.add_repository(@business_org_repo, :pull)
      team2 = create :team, organization: @business_org
      team2.add_repository(@business_org_repo, :pull)

      team_ids = @business_org_repo.actor_ids_for_team_on_repo(action: :read, actor_ids: [team1.id])
      refute_includes team_ids, team2.id
      assert_equal [team1.id], team_ids
    end

    test "filter based on min_action and actor_ids" do
      team1 = create :team, organization: @business_org
      team1.add_repository(@business_org_repo, :pull)
      team2 = create :team, organization: @business_org
      team2.add_repository(@business_org_repo, :pull)

      team_ids = @business_org_repo.actor_ids_for_team_on_repo(min_action: :read, actor_ids: [team1.id])
      assert_equal [team1.id], team_ids
    end

    test "cannot filter with min_action on role based permissions" do
      assert_raises(ArgumentError) do
        @business_org_repo.actor_ids_for_team_on_repo(min_action: :triage)
      end
    end

    test "filter based on role and actor_ids" do
      team1 = create :team, organization: @business_org
      team1.add_repository(@business_org_repo, :maintain)
      team2 = create :team, organization: @business_org
      team2.add_repository(@business_org_repo, :maintain)

      team_ids = @business_org_repo.actor_ids_for_team_on_repo(action: :maintain, actor_ids: [team2.id])

      refute_includes team_ids, team1.id
      assert_equal [team2.id], team_ids
    end

    test "does not include all repo role assignments by default" do
      team1 = create :team, organization: @business_org
      team1.add_repository(@business_org_repo, :read)

      all_repo_read_team = create :team, organization: @business_org
      assert @business_org.grant_org_role(assignee: all_repo_read_team, role: OrganizationRole.all_repo_read_role).success?

      team_ids = @business_org_repo.actor_ids_for_team_on_repo
      refute_includes team_ids, all_repo_read_team.id
      assert_includes team_ids, team1.id
    end

    test "includes all repo role assignments when specified" do
      team1 = create :team, organization: @business_org
      team1.add_repository(@business_org_repo, :read)

      all_repo_read_team = create :team, organization: @business_org
      assert @business_org.grant_org_role(assignee: all_repo_read_team, role: OrganizationRole.all_repo_read_role).success?

      team_ids = @business_org_repo.actor_ids_for_team_on_repo(include_all_repo_roles: true)
      assert_same_elements team_ids, [team1.id, all_repo_read_team.id]
    end

    test "filters all repo role assignments on actor_ids" do
      team1 = create :team, organization: @business_org
      team1.add_repository(@business_org_repo, :read)

      all_repo_read_team = create :team, organization: @business_org
      assert @business_org.grant_org_role(assignee: all_repo_read_team, role: OrganizationRole.all_repo_read_role).success?

      all_repo_read_team2 = create :team, organization: @business_org
      assert @business_org.grant_org_role(assignee: all_repo_read_team2, role: OrganizationRole.all_repo_read_role).success?

      team_ids = @business_org_repo.actor_ids_for_team_on_repo(actor_ids: [team1.id, all_repo_read_team.id], include_all_repo_roles: true)
      assert_same_elements team_ids, [team1.id, all_repo_read_team.id]
    end

    test "filters all repo role assignments on min_action" do
      all_repo_read_team = create :team, organization: @business_org
      assert @business_org.grant_org_role(assignee: all_repo_read_team, role: OrganizationRole.all_repo_read_role).success?

      all_repo_write_team = create :team, organization: @business_org
      assert @business_org.grant_org_role(assignee: all_repo_write_team, role: OrganizationRole.all_repo_write_role).success?

      all_repo_maintain_team = create :team, organization: @business_org
      assert @business_org.grant_org_role(assignee: all_repo_maintain_team, role: OrganizationRole.all_repo_maintain_role).success?

      team_ids = @business_org_repo.actor_ids_for_team_on_repo(min_action: :write, include_all_repo_roles: true)
      assert_same_elements team_ids, [all_repo_write_team.id, all_repo_maintain_team.id]
    end

    test "does not filter out teams with both direct and all repo role assignments based on action" do
      mixed_team = create :team, organization: @business_org
      mixed_team.add_repository(@business_org_repo, :pull)
      assert @business_org.grant_org_role(assignee: mixed_team, role: OrganizationRole.all_repo_read_role).success?

      assert_includes @business_org_repo.actor_ids_for_team_on_repo(action: :read), mixed_team.id
    end
  end

  context "addable_teams_for" do
    test "includes all visible teams for an org member with admin on the repo" do
      org    = create(:organization)
      repo   = create(:repository, owner: org)
      member = create(:user, login: "member")
      org.add_member(member)
      repo.add_member(member, action: :admin)

      secret_team = create(:team, organization: org, name: "secret-team", privacy: :secret)
      team_without_membership = create(:team, organization: org, name: "without-membership", privacy: :closed)
      team_with_membership = create(:team, organization: org, name: "with-membership", privacy: :closed)
      team_with_membership.add_member(member)

      assert_same_elements [team_with_membership, team_without_membership], repo.addable_teams_for(member)
    end

    test "empty for an outside collaborator with admin on the repo" do
      org            = create(:organization)
      repo           = create(:repository, owner: org)
      outside_collab = create(:user, login: "outside-collab")

      create :team, organization: org
      repo.add_member(outside_collab, action: :admin)

      assert_empty repo.addable_teams_for(outside_collab)
    end

    test "includes no teams if the user has read on the repo" do
      org    = create(:organization)
      repo   = create(:repository, owner: org)
      member = create(:user, login: "member")
      org.add_member(member, action: :read)

      # The member needs to be a team maintainer for this to work, since users
      # must have admin on a team to add repos to it, and the member
      # intentionally isn't an org admin in this test.
      addable_team = create(:team, organization: org, name: "addable")
      addable_team.add_member(member)
      addable_team.promote_maintainer(member)

      assert_empty repo.addable_teams_for(member)
    end
  end

  context "can_add_to_team?" do
    test "true when the adder has admin on the repo and team" do
      admin_team_1 = create(:team, organization: @org1, name: "admin-team-1", permission: "admin")
      admin_team_1.add_member(@user)
      admin_team_1.add_repository(@repo, :admin)

      admin_team_2 = create(:team, organization: @org1, name: "admin-team-2", permission: "admin")
      admin_team_2.add_member(@user)

      assert @repo.can_add_to_team?(admin_team_2, adder: @user)
      assert @repo.can_add_to_team?(admin_team_2, adder: @owner)
    end

    test "false when the repo has already been added to the team" do
      admin_team = create(:team, organization: @org1, name: "admin-team", permission: "admin")
      admin_team.add_member(@user)
      admin_team.add_repository(@repo, :admin)

      refute @repo.can_add_to_team?(admin_team, adder: @user)
      refute @repo.can_add_to_team?(admin_team, adder: @owner)
    end

    test "false when the adder doesn't have admin on the repo" do
      read_member = create(:user, login: "read-member")
      @org1.add_member(read_member, action: :read)

      admin_member = create(:user, login: "admin-member")
      @org1.add_member(admin_member, action: :admin)

      team = create :team, organization: @org1

      refute @repo.can_add_to_team?(team, adder: read_member)
      assert @repo.can_add_to_team?(team, adder: admin_member)
    end
  end

  test "knows who can read", skip_with_all_emus: true do
    org = create :organization, plan: "bronze"
    repo = create(:private_repository, owner: org)
    team = create :team, organization: org, permission: "pull"
    status = team.add_repository(repo, "pull")
    assert status.success?, status.status.to_s
    team.add_member @defunkt
    assert repo.pullable_by?(@defunkt)
    refute repo.pushable_by?(@defunkt)
    refute repo.adminable_by?(@defunkt)
    refute repo.pullable_by?(@mojombo)
  end

  test "knows who can write", skip_with_all_emus: true do
    org = create :organization, plan: "bronze"
    repo = create(:private_repository, owner: org)
    team = create :team, organization: org, permission: "admin"
    status = team.add_repository(repo, "push")
    assert status.success?, status.status.to_s
    team.add_member @defunkt

    assert repo.pullable_by?(@defunkt)
    assert repo.pushable_by?(@defunkt)
    refute repo.adminable_by?(@defunkt)
    refute repo.pullable_by?(@mojombo)
  end

  context "#issues_and_prs_linkable_by?" do
    test "returns false if user is read only" do
      org    = create(:organization, plan: "bronze")
      repo   = create(:private_repository, owner: org)
      member = create(:user, login: "read-member")

      org.add_member(member, action: :read)

      refute repo.issues_and_prs_linkable_by?(member)
    end

    test "returns false if repo is locked" do
      org    = create(:organization, plan: "bronze")
      repo   = create(:private_repository, owner: org, locked: true)
      member = create(:user, login: "admin-member")

      org.add_member(member, action: :admin)

      refute repo.issues_and_prs_linkable_by?(member)
    end

    test "returns true if user is admin" do
      org    = create(:organization, plan: "bronze")
      repo   = create(:private_repository, owner: org)
      member = create(:user, login: "admin-member")

      org.add_member(member, action: :admin)

      assert repo.issues_and_prs_linkable_by?(member)
    end
  end

  context "#pushable_by?" do
    test "returns false if user is an installation with read permission on repository" do
      installation = make_integration_installation(repository: @simple,
                                                  permissions: { "contents" => :read })

      refute @simple.pushable_by?(installation)
    end

    test "returns true if user is an installation with write permission on repository" do
      installation = make_integration_installation(repository: @simple,
                                                  permissions: { "contents" => :write })

      assert @simple.pushable_by?(installation)
    end

    test "returns false if repo is locked" do
      @simple.lock!("tos")
      assert @simple.authorized_to_write?(@simple.owner)
      refute @simple.pushable_by?(@simple.owner)
    end

    test "returns false if repo is locked for migration" do
      @simple.lock_for_migration
      assert @simple.authorized_to_write?(@simple.owner)
      refute @simple.pushable_by?(@simple.owner)
    end

    test "returns false if repo is archived" do
      @simple.set_archived
      assert @simple.authorized_to_write?(@simple.owner)
      refute @simple.pushable_by?(@simple.owner)
    end
  end

  test "PR to forked repository with fork_collab permissions does allow maintainer write access" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    default_branch = "master"

    maintainer = create :user, login: "maintainer", plan: "medium"
    main_repo = create :repository, owner: maintainer, from_example: :simple

    contributor = create :user, login: "contributor"

    # stage 1 - contributor forks the repository
    forked_repo = create(:fork_repository, forker: contributor, fork_repo: main_repo, create_owner: true, from_example: :simple)

    # stage 2 - contributor makes a commit to forked repository to move it ahead
    branch = forked_repo.refs.find(default_branch)
    branch.append_commit({ message: "Commit on #{default_branch}", committer: contributor }, contributor) do |files|
      files.add("Newer file", "New file")
    end

    # stage 3 - pull request created to update secondary fork from first fork (without fork_collab permissions)
    pull = PullRequest.create_for!(main_repo,
      user: contributor,
      title: "Repair broken widgets (my fork)",
      body: "We have to repair this widget before we can continue.",
      base: "#{main_repo.owner}:master",
      head: "#{forked_repo.owner}:master",
    )

    # confirm fork is in the right direction
    assert_equal pull.head_repository.id, forked_repo.id
    assert_equal pull.base_repository.id, main_repo.id

    assert_equal 1, PullRequest.find_open_ids_based_on_head_ref(forked_repo.id, default_branch).count

    # confirm "maintainer can modify" checkbox was not set
    refute pull.fork_collab_granted?

    # maintainer is unable to push to original fork (expected behaviour)
    refute forked_repo.pushable_by?(maintainer, ref: default_branch)

    # verify stat shows the authn request was denied
    stats = GitHub.dogstats.increments("authentication.fork_collab")
    assert_equal 1, stats.length
    assert_includes stats.first.tags, "result:denied"

    # update the pull request to enable fork_collab permissions
    pull.fork_collab_state = :allowed
    pull.save!

    # confirm "maintainer can modify" checkbox was set
    assert pull.fork_collab_granted?

    # maintainer is able to push to original fork (expected behaviour)
    assert forked_repo.pushable_by?(maintainer, ref: default_branch)

    # verify stat shows the authn request was granted
    stats = GitHub.dogstats.increments("authentication.fork_collab")
    assert_equal 2, stats.length
    assert_includes stats[1].tags, "result:granted"
  end

  test "PR from forked repository to own account does not allow contributor write access to forked repository", skip_with_all_emus: true do
    default_branch = "master"

    maintainer = create :user, login: "maintainer", plan: "medium"
    main_repo = create :repository, owner: maintainer, from_example: :simple

    contributor = create :user, login: "contributor"
    nefarious_user = create :user, login: "nefarious-user"

    # stage 1 - contributor forks main repository
    forked_repo = create(:fork_repository, forker: contributor, fork_repo: main_repo, from_example: :simple)

    # stage 2 - add the nefarious user to the fork
    # this is required so that they can create a PR with "maintainer can modify"
    # set on the base branch (i.e. the original fork)
    forked_repo.add_member nefarious_user

    # stage 3 - nefarious user forks forked repository to their own account
    nefarious_fork = create(:fork_repository, forker: nefarious_user, fork_repo: forked_repo, from_example: :simple)

    # stage 4a - contributor makes a commit to forked repository to move it ahead
    branch = forked_repo.refs.find(default_branch)
    branch.append_commit({ message: "Commit on #{default_branch}", committer: contributor }, contributor) do |files|
      files.add("Newer file", "New file")
    end

    # stage 4b - pull request created to update secondary fork from first fork
    pull = PullRequest.create_for!(nefarious_fork,
      user: nefarious_fork.owner,
      title: "Repair broken widgets (my fork)",
      body: "We have to repair this widget before we can continue.",
      base: "nefarious-user:master",
      head: "contributor:master",
      maintainer_can_modify: true
    )

    # confirm fork is in the right direction
    assert_equal pull.head_repository.id, forked_repo.id
    assert_equal pull.base_repository.id, nefarious_fork.id

    # confirm "maintainer can modify" checkbox was set
    assert pull.fork_collab_granted?

    assert_equal 1, PullRequest.find_open_ids_based_on_head_ref(forked_repo.id, default_branch).count

    # now remove the collaborator from the original fork
    perform_enqueued_jobs(only: [DenyForkCollabStateForUserPullRequestsJob, RemoveUserFromRepoCleanupJob]) do
      forked_repo.remove_member nefarious_user
    end

    # nefarious user is unable to push to original fork (expected behaviour)
    refute forked_repo.pushable_by?(nefarious_user, ref: default_branch)
  end

  test "PR from forked repository to own account does not allow contributor write access to forked repository if membership downgraded", skip_with_all_emus: true do
    owner = create(:user, login: "org-admin")

    org = create(:organization, login: "org", admin: owner)
    org.allow_private_repository_forking(actor: owner)

    default_branch = "master"

    contributor = create :user, login: "contributor"
    main_repo = create :repository, owner: contributor, from_example: :simple

    nefarious_user = create :user, login: "nefarious-user"

    # stage 1 - owner forks main repository
    forked_repo = create(:fork_repository, forker: owner, fork_repo: main_repo, organization: org, from_example: :simple)

    # stage 2 - add the nefarious user to the fork
    # this is required so that they can create a PR with "maintainer can modify"
    # set on the base branch (i.e. the original fork)
    forked_repo.add_member nefarious_user

    # stage 3 - nefarious user forks forked repository to their own account
    nefarious_fork = create(:fork_repository, forker: nefarious_user, fork_repo: forked_repo, from_example: :simple)

    # stage 4a - contributor makes a commit to forked repository to move it ahead
    branch = forked_repo.refs.find(default_branch)
    branch.append_commit({ message: "Commit on #{default_branch}", committer: owner }, owner) do |files|
      files.add("Newer file", "New file")
    end

    # stage 4b - pull request created to update secondary fork from first fork
    pull = create(:pull_request,
      user: nefarious_user,
      repository: nefarious_fork,
      base_repository: nefarious_fork,
      base_user: nefarious_fork.owner,
      base_ref: "master",
      head_repository: forked_repo,
      head_user: forked_repo.owner,
      head_ref: "master",
      issue: create(:issue, repository: nefarious_fork, user: nefarious_user),
      fork_collab_state: :allowed
    )

    # confirm fork is in the right direction
    assert_equal pull.head_repository.id, forked_repo.id
    assert_equal pull.base_repository.id, nefarious_fork.id

    # confirm "maintainer can modify" checkbox was set
    assert pull.fork_collab_granted?

    assert_equal 1, PullRequest.find_open_ids_based_on_head_ref(forked_repo.id, default_branch).count

    # now downgraded the user's permissions from :write to :read
    forked_repo.update_member(nefarious_user, action: :read)

    # nefarious user is unable to push to original fork (expected behaviour)
    refute forked_repo.pushable_by?(nefarious_user, ref: default_branch)
  end

  test "PR from forked repository under org to own account does not allow contributor write access to org repository", skip_with_all_emus: true do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    default_branch = "master"

    maintainer = create :user, login: "maintainer", plan: "medium"
    main_repo = create :repository, owner: maintainer, from_example: :simple

    org = create :organization, login: "some-org", admins: [maintainer]
    nefarious_user = create :user, login: "nefarious-user"

    # stage 1 - contributor forks main repository into org
    forked_repo = create(:fork_repository, forker: maintainer, fork_repo: main_repo, organization: org, from_example: :simple)

    # create a team under the org which has write permissions to the fork
    team = create :team, organization: org
    team.add_repository(forked_repo, :write)

    # stage 2 - add the nefarious user to the team
    # this is required so that they can create a PR with "maintainer can modify"
    # set on the base branch in the original fork)
    team.add_member nefarious_user

    # stage 3 - nefarious user forks forked repository to their own account
    nefarious_fork = create(:fork_repository, forker: nefarious_user, fork_repo: forked_repo, from_example: :simple)

    # stage 4a - contributor makes a commit to forked repository to move it ahead
    branch = forked_repo.refs.find(default_branch)
    branch.append_commit({ message: "Commit on #{default_branch}", committer: maintainer }, maintainer) do |files|
      files.add("Newer file", "New file")
    end

    # stage 4b - pull request created to update secondary fork from first fork
    pull = PullRequest.create_for!(nefarious_fork,
      user: nefarious_fork.owner,
      title: "Repair broken widgets (my fork)",
      body: "We have to repair this widget before we can continue.",
      base: "nefarious-user:master",
      head: "some-org:master",
      maintainer_can_modify: true
    )

    # confirm fork is in the right direction
    assert_equal pull.head_repository.id, forked_repo.id
    assert_equal pull.base_repository.id, nefarious_fork.id

    # confirm "maintainer can modify" checkbox was set
    assert pull.fork_collab_granted?

    assert_equal 1, PullRequest.find_open_ids_based_on_head_ref(forked_repo.id, default_branch).count

    # now remove the collaborator from the org that owns the original fork
    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob, RemoveOrgMemberForksJob, DenyForkCollabStateForUserPullRequestsJob]) do
      org.remove_member nefarious_user
    end

    # nefarious user is unable to push to original fork (expected behaviour)
    refute forked_repo.pushable_by?(nefarious_user, ref: default_branch)

    stats = GitHub.dogstats.increments("authentication.fork_collab")
    assert_equal 1, stats.length
    assert_includes stats.first.tags, "result:denied"
  end

  test "PR from forked repository under org to own account does not allow contributor write access to org repository if removed from team", skip_with_all_emus: true do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    default_branch = "master"

    maintainer = create :user, login: "maintainer", plan: "medium"
    main_repo = create :repository, owner: maintainer, from_example: :simple

    org = create :organization, login: "some-org", admins: [maintainer]
    nefarious_user = create :user, login: "nefarious-user"

    # stage 1 - contributor forks main repository into org
    forked_repo = create(:fork_repository, forker: maintainer, fork_repo: main_repo, organization: org, from_example: :simple)

    # create a team under the org which has write permissions to the fork
    team = create :team, organization: org
    team.add_repository(forked_repo, :write)

    # stage 2 - add the nefarious user to the team
    # this is required so that they can create a PR with "maintainer can modify"
    # set on the base branch in the original fork)
    team.add_member nefarious_user

    # stage 3 - nefarious user forks forked repository to their own account
    nefarious_fork = create(:fork_repository, forker: nefarious_user, fork_repo: forked_repo, from_example: :simple)

    # stage 4a - contributor makes a commit to forked repository to move it ahead
    branch = forked_repo.refs.find(default_branch)
    branch.append_commit({ message: "Commit on #{default_branch}", committer: maintainer }, maintainer) do |files|
      files.add("Newer file", "New file")
    end

    # stage 4b - pull request created to update secondary fork from first fork
    pull = PullRequest.create_for!(nefarious_fork,
      user: nefarious_fork.owner,
      title: "Repair broken widgets (my fork)",
      body: "We have to repair this widget before we can continue.",
      base: "nefarious-user:master",
      head: "some-org:master",
      maintainer_can_modify: true
    )

    # confirm fork is in the right direction
    assert_equal pull.head_repository.id, forked_repo.id
    assert_equal pull.base_repository.id, nefarious_fork.id

    # confirm "maintainer can modify" checkbox was set
    assert pull.fork_collab_granted?

    assert_equal 1, PullRequest.find_open_ids_based_on_head_ref(forked_repo.id, default_branch).count

    # now remove the collaborator from the org that owns the original fork
    perform_enqueued_jobs(only: [DenyForkCollabStateForUserPullRequestsJob]) do
      team.remove_member nefarious_user
    end

    # nefarious user is unable to push to original fork (expected behaviour)
    refute forked_repo.pushable_by?(nefarious_user, ref: default_branch)

    stats = GitHub.dogstats.increments("authentication.fork_collab")
    assert_equal 1, stats.length
    assert_includes stats.first.tags, "result:denied"
  end

  context "#async_pushable_by?" do
    test "returns true if user is collaborator on user-owned repository" do
      repo = create(:private_repository, owner: @mojombo, force_user_owned: true)
      repo.add_member(@defunkt)

      assert repo.async_pushable_by?(@defunkt).sync
    end

    test "returns true if user is member of team with write permission to organization-owned repository" do
      org = create :organization, plan: "bronze"
      repo = create(:private_repository, owner: org)
      team = create :team, organization: org, permission: "push"
      team.add_repository(repo, "push")
      team.add_member(@defunkt)

      assert repo.async_pushable_by?(@defunkt).sync
    end

    test "returns false if user is installation bot with read permission on repository" do
      integration  = create(:integration, default_permissions: { "contents" => :read })
      make_integration_installation(integration: integration, repository: @simple)

      refute @simple.async_pushable_by?(integration.bot).sync
    end

    test "returns true if user is installation bot with write permission on repository" do
      integration  = create(:integration, default_permissions: { "contents" => :write })
      make_integration_installation(integration: integration, repository: @simple)

      assert @simple.async_pushable_by?(integration.bot).sync
    end

    test "returns false if user is a programmatic access bot with read permission on repository", skip_with_all_emus: true do
      access = create(:user_programmatic_access, owner: @defunkt)
      grant = make_programmatic_access_grant(
        access: access, target: @defunkt, actor: @defunkt,
        permissions: { "contents" => :read },
        repositories: [@simple], repository_selection: :subset
      )
      access.bot.grant = grant

      refute @simple.async_pushable_by?(access.bot).sync
    end

    test "returns true if user is a programmatic access bot with write permission on repository", skip_with_all_emus: true do
      access = create(:user_programmatic_access, owner: @defunkt)
      grant = make_programmatic_access_grant(
        access: access, target: @defunkt, actor: @defunkt,
        permissions: { "contents" => :write },
        repositories: [@simple], repository_selection: :subset
      )
      access.bot.grant = grant

      assert @simple.async_pushable_by?(access.bot).sync
    end

    test "returns false if an organization is given" do
      org = create :organization
      refute @simple.async_pushable_by?(org).sync
    end
  end

  context "#owner_on_per_seat_plan?" do
    test "is true for organizations on per seat plans" do
      org = create(:business_organization)
      repo = create(:repository, owner: org)

      assert_predicate repo, :owner_on_per_seat_plan?
    end

    test "is false for organizations not on per seat plans", skip_with_all_emus: true do
      org = create(:organization)
      repo = create(:repository, owner: org)

      refute_predicate repo, :owner_on_per_seat_plan?
    end

    test "is false for users", skip_with_all_emus: true do
      repo = create(:repository)

      refute_predicate repo, :owner_on_per_seat_plan?
    end

    test "does not execute extra queries" do
      org1 = create(:business_organization)
      org2 = create(:enterprise_linked_organization)
      org3 = create(:enterprise_linked_organization)
      repo1 = create(:repository, owner: org1)
      repo2 = create(:repository, owner: org2)
      repo3 = create(:repository, owner: org3)
      repos = [repo1, repo2, repo3]
      repos.each { |repo| repo.reload }
      business_query_count = GitHub.single_business_environment? ? 0 : 1

      assert_query_count_per_table({ users: 1, businesses: business_query_count }) do
        GitHub::PrefillAssociations.prefill_batch_method(repos, :owner_on_per_seat_plan?)
        repos.each { |repo| repo.owner_on_per_seat_plan? }
      end
    end
  end

  if GitHub.public_push_enabled?
    test "knows who can write on private public-push repositories" do
      @ambition.add_member(@mojombo)
      @ambition.update_attribute(:public_push, true)
      assert @ambition.pushable_by?(@defunkt)
      assert @ambition.pushable_by?(@mojombo)
      refute @ambition.pushable_by?(@pj)
    end

    test "knows who can write public-push repositories" do
      @grit.update_attribute(:public_push, true)
      assert @grit.pushable_by?(@defunkt)
      assert @grit.pushable_by?(@mojombo)
      assert @grit.pushable_by?(@pj)
    end
  else
    test "ignores public push" do
      @grit.update_attribute(:public_push, true)
      assert @grit.pushable_by?(@mojombo)
      refute @grit.pushable_by?(@defunkt)
      refute @grit.pushable_by?(@pj)
    end
  end
end

class EmuRepositoryOrganizationsDependencyTest < GitHub::TestCase
  skip_with_all_emus

  include OrganizationOwnedRepoSharedTests

  fixtures do
    @owner = create(:emu, :owner)
    business = @owner.enterprise_managed_business

    @org1 = create(:organization, business: business, admin: @owner)
    @repo = create(:private_repository, owner: @org1)
  end
end unless GitHub.single_business_environment?

class RepositoryAllTeamMembersTest < GitHub::TestCase
  fixtures do
    @org_admin = create(:user, login: "org-admin")
    @org       = create(:organization, admin: @org_admin)
    @team      = create(:team, organization: @org)

    @repo = create(:private_repository, owner: @org)
    @team.add_repository(@repo, :pull)

    @team_member = create(:user, login: "team-member")
    @team.add_member(@team_member)
  end

  test "includes owners when include_org_admins is true" do
    assert_same_elements [@team_member, @org_admin], @repo.all_team_members(include_org_admins: true)
  end

  test "excludes owners when include_org_admins is false" do
    assert_same_elements [@team_member], @repo.all_team_members(include_org_admins: false)
  end
end

class RepositoryAllTeamMemberIdsTest < GitHub::TestCase
  fixtures do
    @org_admin = create(:user, login: "org-admin")
    @org       = create(:organization, admin: @org_admin)
    @team      = create(:team, organization: @org)

    @repo = create(:private_repository, owner: @org)
    @team.add_repository(@repo, :pull)

    @team_member = create(:user, login: "team-member")
    @team.add_member(@team_member)
    @rando = create(:user, login: "rando")
  end

  test "includes private owners when include_org_admins is true and neither viewer nor hide_private_org_owners are not passed" do
    assert_same_elements [@team_member.id, @org_admin.id], @repo.all_team_member_ids(include_org_admins: true)
  end

  test "includes private owners when include_org_admins is true and viewer is an org member" do
    assert_same_elements [@team_member.id, @org_admin.id], @repo.all_team_member_ids(include_org_admins: true, viewer: @org_admin)
  end

  test "does not includes private owners when include_org_admins is true and hide_private_org_owners is true" do
    assert_same_elements [@team_member.id], @repo.all_team_member_ids(include_org_admins: true, hide_private_org_owners: true)
  end

  test "does not includes private owners when viewer is not an org member and hide_private_org_owners is true" do
    assert_same_elements [@team_member.id], @repo.all_team_member_ids(include_org_admins: true, viewer: @rando, hide_private_org_owners: true)
  end
end

class RepositoryVisibleTeamsForTest < GitHub::TestCase
  test "returns no teams if the repository isn’t in an organization" do
    user = create(:user)
    repo = create(:repository, owner: user)
    assert_empty repo.visible_teams_for(user)
  end

  test "returns all teams with repo access for org owner" do
    org_admin = create(:user, login: "org-admin")
    org       = create(:organization, admin: org_admin)
    repo      = create(:repository, owner: org)
    user      = create(:user, login: "user")
    team_1    = create(:team, organization: org, name: "A team")
    team_2    = create(:team, organization: org, name: "B team")
    team_3    = create(:team, organization: org, name: "C team")

    org.add_member(user, action: :admin)
    team_1.add_repository(repo, :admin)
    team_2.add_repository(repo, :pull)

    assert_same_elements [team_1, team_2], repo.visible_teams_for(user)
  end

  test "returns closed but not secret teams with repo access for installation Bot with administration read permissions" do
    org_admin = create(:user, login: "org-admin")
    org       = create(:organization, admin: org_admin)
    repo      = create(:repository, owner: org)
    team_1    = create(:team, organization: org, name: "A team", privacy: :secret)
    team_2    = create(:team, organization: org, name: "B team", privacy: :closed)
    team_3    = create(:team, organization: org, name: "C team", privacy: :closed)

    team_1.add_repository(repo, :admin)
    team_2.add_repository(repo, :pull)

    installation = make_integration_installation(repository: repo,
      permissions: { "administration" => :read })

    assert_same_elements [team_2], repo.visible_teams_for(installation.bot)
  end

  test "returns all teams a user can see with repo access for user on admin team" do
    org       = create(:organization)
    repo      = create(:repository, owner: org)
    user      = create(:user, login: "user")
    team_1    = create(:team, organization: org, name: "A team")
    team_2    = create(:team, organization: org, name: "B team")
    team_3    = create(:team, organization: org, name: "C team")

    team_1.add_member(user)
    team_1.add_repository(repo, :admin)
    team_2.add_repository(repo, :pull)

    result = repo.visible_teams_for(user)
    assert_includes result, team_1, "Expected repo team of which user is a member of to be visible"
    refute_includes result, team_2, "Expected team user is not a member of to not be visible even if on another repo admin team"
    refute_includes result, team_3, "Expected team not associated with repo to not be visible to non-admin"
  end

  test "returns only teams an admin collaborator can see regardless of repo access" do
    org_admin = create(:user, login: "org-admin")
    org       = create(:organization, admin: org_admin)
    repo      = create(:repository, owner: org)
    user      = create(:user, login: "user")
    team_1    = create(:team, organization: org, name: "A team")
    team_2    = create(:team, organization: org, name: "B team")

    repo.add_member(user, org_admin, false, action: :admin)
    team_1.add_repository(repo, :pull)
    team_2.add_repository(repo, :pull)

    assert_empty repo.visible_teams_for(user), "Expected user without access to any teams associated with the repo to get an empty response"
  end

  test "returns all teams with repo access visible to user on write team" do
    org       = create(:organization)
    repo      = create(:repository, owner: org)
    user      = create(:user, login: "user")
    team_1    = create(:team, organization: org, privacy: :closed, name: "A team")
    team_2    = create(:team, organization: org, privacy: :secret, name: "B team")
    team_3    = create(:team, organization: org, privacy: :closed, name: "C team")

    team_1.add_member(user)
    team_1.add_repository(repo, :push)
    team_2.add_repository(repo, :pull)

    result = repo.visible_teams_for(user)
    assert_includes result, team_1, "Expected repo team of which user is a member of to be visible"
    refute_includes result, team_2, "Expected secret repo team user is not a member of to not be visible"
    refute_includes result, team_3, "Expected team not associated with repo to not be visible to non-admin"
  end

  test "returns business teams with repo access when enterprise_teams ff is on" do
    business = create(:business)
    enable_feature_flag(:enterprise_teams_crud, business)
    enable_feature_flag(:enterprise_teams_org_assignment, business)
    admin = create(:user)
    org = create(:organization, admin: admin, business: business)
    repo      = create(:repository, owner: org)
    team_1    = create(:team, organization: org, privacy: :closed, name: "A team")
    team_2    = create(:team, organization: org, privacy: :secret, name: "B team")
    team_3    = create(:team, organization: org, privacy: :closed, name: "C team")
    business_team = create(:business_team, business: business, organization_selection_type: :all)
    user      = create(:user, login: "user")
    team_1.add_member(user)
    team_1.add_repository(repo, :push)
    team_2.add_repository(repo, :pull)
    business_team.add_repository(repo, :pull)

    result = repo.visible_teams_for(user)
    assert_includes result, team_1, "Expected repo team of which user is a member of to be visible"
    refute_includes result, team_2, "Expected secret repo team user is not a member of to not be visible"
    refute_includes result, team_3, "Expected team not associated with repo to not be visible to non-admin"
    assert_includes result, business_team, "Expected business team associated with repo to be visible"
  end

  test "returns no teams for write collaborator" do
    org_admin = create(:user, login: "org-admin")
    org       = create(:organization, admin: org_admin)
    repo      = create(:repository, owner: org)
    user      = create(:user, login: "user")
    team_1    = create(:team, organization: org, name: "A team")
    team_2    = create(:team, organization: org, name: "B team")
    team_3    = create(:team, organization: org, name: "C team")

    repo.add_member(user, org_admin, false, action: :write)
    team_1.add_repository(repo, :pull)
    team_2.add_repository(repo, :pull)

    assert_empty repo.visible_teams_for(user)
  end

  test "returns all teams with repo access visible to user on read team" do
    org       = create(:organization)
    repo      = create(:repository, owner: org)
    user      = create(:user, login: "user")
    team_1    = create(:team, organization: org, privacy: :closed, name: "A team")
    team_2    = create(:team, organization: org, privacy: :secret, name: "B team")
    team_3    = create(:team, organization: org, privacy: :closed, name: "C team")

    team_1.add_member(user)
    team_1.add_repository(repo, :pull)
    team_2.add_repository(repo, :pull)

    result = repo.visible_teams_for(user)
    assert_includes result, team_1, "Expected repo team of which user is a member of to be visible"
    refute_includes result, team_2, "Expected secret repo team user is not a member of to not be visible"
    refute_includes result, team_3, "Expected team not associated with repo to not be visible to non-admin"
  end

  test "returns no teams for read collaborator" do
    org_admin = create(:user, login: "org-admin")
    org       = create(:organization, admin: org_admin)
    repo      = create(:repository, owner: org)
    user      = create(:user, login: "user")
    team_1    = create(:team, organization: org, name: "A team")
    team_2    = create(:team, organization: org, name: "B team")
    team_3    = create(:team, organization: org, name: "C team")

    repo.add_member(user, org_admin, false, action: :read)
    team_1.add_repository(repo, :pull)
    team_2.add_repository(repo, :pull)

    assert_empty repo.visible_teams_for(user)
  end

  test "returns teams with all repo role when requested" do
    org_admin = create(:user, login: "org-admin")
    org       = create(:organization, admin: org_admin)
    repo      = create(:repository, owner: org)
    team      = create(:team, organization: org, name: "All repo role team")

    assert org.grant_org_role(assignee: team, role: OrganizationRole.all_repo_read_role).success?

    result = repo.visible_teams_for(org_admin, include_all_repo_roles: true)
    assert_includes result, team, "Expected team assigned an all repo role to be included"
  end
end

class RepositoryUserRelationshipTest < GitHub::TestCase
  include UserOwnedRepoSharedTests

  fixtures do
    User.create_ghost
    @user = create(:user)
    @owner = create(:user)
    @collaborator = create(:user)
    @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
    create(:collaborator, collaborator: @collaborator, repository: @repo)
    @fork = create(:fork_repository, forker: @user, fork_repo: @repo, from_example: :pull_request_fork)

    @pull = PullRequest.create_for! @repo,
      user: @user,
      title: "test PR",
      body: "body",
      base: "#{@repo.owner.login}:master",
      head: "#{@user.display_login}:master-plus-one-commit"

    @issue = create(:issue, repository:  @repo)
    @comment = create(:issue_comment, issue: @issue, user: @collaborator)

    @contributor = create(:user)
    @repo.heads.find("master").append_commit({
      message: "change stuff",
      committer: @contributor,
      author: @contributor,
    }, @contributor)

    CommitContribution.backfill!(@repo)
  end

  test "repo owner returns correct viewer relationship" do
    assert_equal :owner, @repo.async_user_relationship(@owner).sync
  end

  test "repo collaborator returns correct viewer relationship" do
    assert_equal :collaborator, @repo.async_user_relationship(@collaborator).sync
  end

  test "repo contributor returns correct viewer relationship" do
    assert_equal :contributor, @repo.async_user_relationship(@contributor).sync
  end

  test "regular user returns correct viewer relationship" do
    assert_equal :none, @repo.async_user_relationship(@user).sync
  end
end

class EmuRepositoryUserRelationshipTest < GitHub::TestCase
  skip_with_all_emus

  include UserOwnedRepoSharedTests

  fixtures do
    @owner = create(:emu, :owner)
    @repo = create(:repository, owner: @owner)
  end
end unless GitHub.single_business_environment?

class RepositoryUserCanReportTest < GitHub::TestCase
  skip_with_all_emus

  fixtures do
    User.create_ghost
    @user = create(:user)
    @owner = create(:user)
    @collaborator = create(:user)
    @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
    create(:collaborator, collaborator: @collaborator, repository: @repo)
    @fork = create(:fork_repository, forker: @user, fork_repo: @repo, from_example: :pull_request_fork)

    @pull = PullRequest.create_for! @repo,
      user: @user,
      title: "test PR",
      body: "body",
      base: "#{@repo.owner.login}:master",
      head: "#{@user.display_login}:master-plus-one-commit"

    @issue = create(:issue, repository:  @repo)
    @comment = create(:issue_comment, issue: @issue, user: @collaborator)

    @org = create(:organization, admin: @owner)
    @org_member = create(:user)
    @org.add_member(@org_member, action: :read)
    @org_repo = create :repository, owner: @org, name: "org-public", from_example: :pages
    @org_repo.add_member(@collaborator, action: :read)

    @org_issue = create(:issue, repository:  @org_repo)
    @org_comment = create(:issue_comment, issue: @org_issue, user: @user)

    @prior_contributor = create(:user)

    CommitContribution.create!(repository: @repo, user: @prior_contributor, committed_date: Time.now.to_date)
    CommitContribution.create!(repository: @org_repo, user: @prior_contributor, committed_date: Time.now.to_date)
  end

  setup do
    @repo = Repositories::Public.find_active!(@repo.id)
    @org_repo = Repositories::Public.find_active!(@org_repo.id)
  end

  if GitHub.can_report?
    test "cannot report private repository" do
      @repo.private = true
      @repo.save!

      refute @repo.async_user_can_report?(@collaborator).sync
    end

    test "anonymous user cannot report" do
      refute @repo.async_user_can_report?(nil).sync
    end

    test "unaffiliated user cannot report" do
      refute @repo.async_user_can_report?(create(:user)).sync
    end

    test "prior contributor returns nil in user-owned repo" do
      assert_nil @repo.async_user_can_report?(@prior_contributor).sync
    end

    test "prior contributor returns nil in org-owned repo" do
      assert_nil @repo.async_user_can_report?(@prior_contributor).sync
    end

    test "repo member can report" do
      assert @repo.async_user_can_report?(@collaborator).sync
    end

    test "org member can report" do
      assert @org_repo.async_user_can_report?(@org_member).sync
    end

    test "non-repo member returns nil" do
      assert_nil @repo.async_user_can_report?(create(:user)).sync
    end

    test "non-org member returns nil" do
      assert_nil @org_repo.async_user_can_report?(create(:user)).sync
    end

    test "prior contributor blocked by user cannot report" do
      assert_nil @repo.async_user_can_report?(@prior_contributor).sync

      @owner.block(@prior_contributor)

      repo = Repositories::Public.find_active!(@repo.id)
      refute repo.async_user_can_report?(@prior_contributor).sync
    end

    test "prior contributor blocked by org cannot report" do
      assert_nil @org_repo.async_user_can_report?(@prior_contributor).sync

      @org.block(@prior_contributor)

      org_repo = Repositories::Public.find_active!(@org_repo.id)
      refute org_repo.async_user_can_report?(@prior_contributor).sync
    end

    test "collaborator blocked by user is removed and cannot report" do
      assert @repo.writable_by?(@collaborator)

      perform_enqueued_jobs(only: [IgnoreUserJob]) do
        @owner.block(@collaborator)
      end

      refute @repo.writable_by?(@collaborator)
      refute @repo.async_user_can_report?(@collaborator).sync
    end

    test "collaborator blocked by org is removed and cannot report" do
      assert @org_repo.member?(@collaborator)

      perform_enqueued_jobs(only: [IgnoreUserJob]) do
        @org.block(@collaborator)
      end

      refute @org_repo.member?(@collaborator)
      refute @org_repo.async_user_can_report?(@collaborator).sync
    end
  else
    test "repo member cannot report" do
      refute @repo.async_user_can_report?(@owner).sync
    end

    test "org member cannot report" do
      refute @org_repo.async_user_can_report?(@org_member).sync
    end
  end
end
