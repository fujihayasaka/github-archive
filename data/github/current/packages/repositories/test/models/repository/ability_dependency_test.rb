# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAbilityDependencyTest < GitHub::TestCase
  include UnlockedRepositoryCheckTestHelper

  fixtures do
    @admin = create(:user)
    @defunkt  = create(:user, login: "defunkt",  plan: "medium")
    @business = create(:business)
    @org = create(:organization, business: @business)
    @org.add_admin(@admin)
    @repo_owner = create :user
    @user_repo = create :repository, owner: @repo_owner
    @user_private_repo = create :private_repository, owner: @repo_owner
    @other_user = create :user
    @maintain_user = create :user
    @mojombo = create(:user, login: "mojombo2", plan: "medium")
    @org_on_business_plus = create :business_plus_organization, business: @business
    @org_repo = create :repository, owner: @org_on_business_plus
    @org_repo.add_member(@maintain_user)
    @org_private_repo = create(:private_repository, owner: @org_on_business_plus)
    @org_private_repo.allow_private_repository_forking(actor: @admin)
    @team = create(:team, privacy: :closed, organization: @org_on_business_plus)
    @child_team  = create(:team, organization: @org_on_business_plus, privacy: :closed, parent_team_id: @team.id)

    @ambition = create(:private_repository, name: "ambition", owner: @defunkt)
    @facebox  = create(:repository, name: "facebox",  owner: @defunkt)
    @grit     = create(:repository, name: "grit",     owner: @mojombo)
    @simple   = create(:repository, name: "simple",   owner: @defunkt)

    @internal = create(:internal_repository, owner: @org)
    @internal.allow_private_repository_forking(actor: @admin)

    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
      @biz_org = create(:enterprise_linked_organization)
      @biz_org.update_default_repository_permission(:none, actor: @biz_org.admins.first)
    end
    @internal_repo = create(:internal_repository, owner: @biz_org)

    @forker = create(:user)
    @other_org = create(:organization, business: @org_on_business_plus.business)
    @other_org.add_admin(@forker)
    @org_on_business_plus.add_member(@forker)
    @user_private_repo.add_member(@forker)
    @org_private_repo.add_member(@forker)

    # all repo role fixtures
    @arr_user = create(:user)
    @arr_second_user = create(:user)
    @arr_org = create :business_plus_organization
    @arr_org.add_member(@arr_user)
    @arr_org.add_member(@arr_second_user)

    @arr_org_repo = create :repository, owner: @arr_org
    @arr_org_repo_2 = create :repository, owner: @arr_org

    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
      @arr_org.update_default_repository_permission(:none, actor: @arr_org.admins.first)
    end

    @arr_team = create(:team, organization: @arr_org)
    @arr_team.add_member(@arr_user)

    @custom_org_write_role = create(:custom_all_repo_role, base_role_id: Role.write_role.id, owner_id: @arr_org.id, owner_type: "Organization")
    @custom_org_read_role = create(:custom_all_repo_role, base_role_id: Role.read_role.id, owner_id: @arr_org.id, owner_type: "Organization")
  end

  setup do
    @old_private_mode = GitHub.private_mode_enabled?
    GitHub.private_mode = false
    clear_memoized_unlocked_repository_check
  end

  teardown do
    GitHub.private_mode = @old_private_mode
  end

  context "#can_be_interacted_with_by?" do
    test "returns false when interactions are disallowed for the given actor" do
      RepositoryInteractionAbility.new(@user_repo).set_ability(:collaborators_only, @repo_owner)
      refute @user_repo.can_be_interacted_with_by?(@other_user)
    end

    test "returns false for anonymous actor" do
      refute @user_repo.can_be_interacted_with_by?(nil)
    end

    test "returns true when interactions are allowed for the repo by the given actor" do
      assert @user_repo.can_be_interacted_with_by?(@repo_owner)
      assert @user_repo.can_be_interacted_with_by?(@other_user)
    end

    test "respects explicitly provided user_can_push=true" do
      RepositoryInteractionAbility.new(@user_repo).set_ability(:collaborators_only, @repo_owner)
      assert @user_repo.can_be_interacted_with_by?(@other_user, user_can_push: true)
    end
  end

  context "accessible_via_org_admin" do
    test "returns org owned repos for orgs a user has admin on" do
      repo = create(:repository, owner: @org)
      repo1 = create(:repository, owner: @org)
      repo2 = create(:repository, owner: @org)
      repos = [repo.id, repo1.id, repo2.id, @org_repo.id, @user_repo.id]

      results = Repository.accessible_via_org_admin(@admin, repos)

      assert_includes results, repo.id
      assert_includes results, repo1.id
      assert_includes results, repo2.id
      refute_includes results, @org_repo.id
      refute_includes results, @user_repo.id
    end

    test "returns org owned repos for a specified org that a user has admin on" do
      other_org = create(:organization, business: @business)
      other_org.add_admin(@admin)

      org1_repo1 = create(:repository, owner: @org)
      org1_repo2 = create(:repository, owner: @org)
      org2_repo1 = create(:repository, owner: other_org)
      org2_repo2 = create(:repository, owner: other_org)
      repos = [org1_repo1, org1_repo2, org2_repo1, org2_repo2]

      results = Repository.accessible_via_org_admin(@admin, repos, @org.id)

      assert_includes results, org1_repo1.id
      assert_includes results, org1_repo2.id
      refute_includes results, org2_repo1.id
      refute_includes results, org2_repo2.id
      refute_includes results, @user_repo.id
    end

    test "returns none for non org admin" do
      repo   = create(:repository, owner: @org)
      repo2  = create(:repository, owner: @org)
      user   = create :user
      @org.add_member(user)
      repo.add_member(user)

      repos = [repo.id, repo2.id]
      results = Repository.accessible_via_org_admin(user, repos)
      assert_empty results
    end
  end

  context "permit?" do
    context "action :write" do
      test "returns false when actor is a user that has no relationship to repo" do
        repo = create(:private_repository)

        unrelated_user = create(:user)

        refute repo.permit?(unrelated_user, :write)
        refute repo.async_permit?(unrelated_user, :write).sync
      end

      test "returns false when actor is a user that has read access to repo" do
        repo = create(:private_repository)
        collab = create(:user)
        Ability.grant(collab, :read, repo)

        refute repo.permit?(collab, :write)
        refute repo.async_permit?(collab, :write).sync
      end

      test "returns false when actor is the org that owns the repo" do
        org = create(:organization)
        repo = create(:repository, owner: org)

        refute repo.permit?(org, :write)
        refute repo.async_permit?(org, :write).sync
      end

      test "returns false when actor is a user with internal permissions on a repo" do
        business = Business.first || create(:business)
        org = create(:organization, business: business)
        org_member = create(:user)
        org.add_member(org_member)
        repo = create(:internal_repository, owner: org)

        refute repo.permit?(org_member, :write)
        refute repo.async_permit?(org_member, :write).sync
      end

      test "returns the actor maximum access when it is a user with org roles with write_repo base role permission" do
        GitHub.flipper.enable(:all_repo_roles)

        org_member = create(:user)
        @org_on_business_plus.add_member(org_member)
        custom_org_role = create(:custom_all_repo_role, base_role_id: Role.write_role.id, owner_id: @org_on_business_plus.id, owner_type: "Organization")
        @org_on_business_plus.grant_org_role(assignee: org_member, role: custom_org_role)

        assert @org_repo.permit?(org_member, :write)
        assert_equal :write, @org_repo.async_access_level_for(org_member).sync
      end

      test "returns the actor maximum access when it is a user with org roles with admin_repo base role permission" do
        GitHub.flipper.enable(:all_repo_roles)

        org_member = create(:user)
        @org_on_business_plus.add_member(org_member)
        custom_org_role = create(:custom_all_repo_role, base_role_id: Role.admin_role.id, owner_id: @org_on_business_plus.id, owner_type: "Organization")
        @org_on_business_plus.grant_org_role(assignee: org_member, role: custom_org_role)

        assert @org_repo.permit?(org_member, :admin)
        assert_equal :admin, @org_repo.async_access_level_for(org_member).sync
      end

      test "returns true when actor is a user with org roles with base role permission" do
        GitHub.flipper.enable(:all_repo_roles)

        org_member = create(:user)
        @org_on_business_plus.add_member(org_member)
        custom_org_role = create(:custom_all_repo_role, base_role_id: Role.write_role.id, owner_id: @org_on_business_plus.id, owner_type: "Organization")
        @org_on_business_plus.grant_org_role(assignee: org_member, role: custom_org_role)

        assert @org_repo.permit?(org_member, :write)
        assert @org_repo.async_permit?(org_member, :write).sync
      end

      test "returns true when actor is a user that is owner of repo" do
        repo = create(:private_repository)

        assert repo.permit?(repo.owner, :write)
        assert repo.async_permit?(repo.owner, :write).sync
      end

      test "returns false when actor is an IntegrationInstallation with Repository/contents write access" do
        integration = create(:integration, default_permissions: { "contents" => :write })
        repo = create(:private_repository)
        installation = make_integration_installation(integration: integration, repository: repo)

        refute repo.permit?(installation, :write)
        refute repo.async_permit?(installation, :write).sync
      end

      test "returns true when user has unlocked the repository" do
        user = create :staff_admin_user, stafftools_roles: %w[can-unlock-repos-with-owners-permission can-unlock-repos-without-owners-permission]
        repo = create(:private_repository)
        repo.staff_access_grants.create(granted_by: user, reason: "just because")
        user.unlock_repository(repo, "just because")

        assert repo.reload.permit?(user, :write)
        assert repo.reload.async_permit?(user, :write).sync
      end

      if GitHub.enterprise?
        test "returns true for public push (Enterprise-only)" do
          user = create(:user)
          repo = create(:public_repository, public_push: true)

          assert repo.permit?(user, :write)
          assert repo.async_permit?(user, :write).sync
        end
      end
    end

    context "action :read" do
      test "returns true when actor is organization owner" do
        org = create(:organization)
        repo = create(:private_repository, owner: org)

        assert repo.permit?(org.admin, :read)
        assert repo.async_permit?(org.admin, :read).sync
      end

      test "returns false when actor is a user that has no relationship to repo" do
        repo = create(:private_repository)

        unrelated_user = create(:user)

        refute repo.permit?(unrelated_user, :read)
        refute repo.async_permit?(unrelated_user, :read).sync
      end

      test "returns true when actor is a user that has read access to repo" do
        repo = create(:private_repository)
        collab = create(:user)
        Ability.grant(collab, :read, repo)

        assert repo.permit?(collab, :read)
        assert repo.async_permit?(collab, :read).sync
      end

      test "returns true for business member for internal repo" do
        # this test case asserts implicit access over the repo
        org_member = create(:user)
        @biz_org.add_member(org_member)

        assert @internal_repo.permit?(org_member, :read)
        assert @internal_repo.async_permit?(org_member, :read).sync
      end

      test "returns false for business member flagged as contractor for internal repo" do
        GitHub.stubs(:restrict_contractors_from_default_access_to_internal_repos?).returns(true)

        # this test case refutes implicit access over the repo
        org_member = create(:user, :contractor)
        @biz_org.add_member(org_member)

        refute @internal_repo.permit?(org_member, :read)
        refute @internal_repo.async_permit?(org_member, :read).sync
      end

      test "returns true for business member flagged as contractor with team membership" do
        GitHub.stubs(:restrict_contractors_from_default_access_to_internal_repos?).returns(true)

        # this test case asserts explicit indirect access over the repo
        team = create(:team, organization: @biz_org)
        org_member = create(:user, :contractor)
        team.add_member(org_member)
        team.add_repository(@internal_repo, :pull)

        assert @internal_repo.permit?(org_member, :read)
        assert @internal_repo.async_permit?(org_member, :read).sync
      end

      test "returns true for business member flagged as contractor with direct access" do
        GitHub.stubs(:restrict_contractors_from_default_access_to_internal_repos?).returns(true)

        # this test case asserts explicit direct access over the repo
        org_member = create(:user, :contractor)
        @internal_repo.add_member(org_member)

        assert @internal_repo.permit?(org_member, :read)
        assert @internal_repo.async_permit?(org_member, :read).sync
      end

      test "returns true when actor is a user that is owner of repo" do
        repo = create(:private_repository)

        assert repo.permit?(repo.owner, :read)
        assert repo.async_permit?(repo.owner, :read).sync
      end

      test "returns false when actor is an IntegrationInstallation with Repository/contents read access" do
        integration = create(:integration, default_permissions: { "contents" => :read })
        repo = create(:private_repository)
        installation = make_integration_installation(integration: integration, repository: repo)

        refute repo.permit?(installation, :read)
        refute repo.async_permit?(installation, :read).sync
      end

      test "returns true when actor is anonymous and repo is public" do
        repo = create(:repository)
        assert repo.permit?(nil, :read)
        assert repo.async_permit?(nil, :read).sync
      end

      test "returns false when actor is anonymous and repo is public and private mode is enabled" do
        GitHub.private_mode = true
        repo = create(:repository)
        refute repo.permit?(nil, :read)
        refute repo.async_permit?(nil, :read).sync
      end
    end
  end

  context "user_ids_with_privileged_access" do
    test "returns users with all repo role access" do
      refute_includes(@arr_org_repo.user_ids_with_privileged_access, @arr_user.id)
      @arr_org.grant_org_role(assignee: @arr_user, role: @custom_org_read_role)
      assert_includes(@arr_org_repo.user_ids_with_privileged_access, @arr_user.id)
    end

    test "returns users from teams with all repo roles access" do
      team_member_ids = @arr_team.members.map(&:id)
      team_member_ids.each do |user_id|
        refute_includes(@arr_org_repo.user_ids_with_privileged_access, user_id)
      end

      @arr_org.grant_org_role(assignee: @arr_team, role: @custom_org_read_role)

      team_member_ids.each do |user_id|
        assert_includes(@arr_org_repo.user_ids_with_privileged_access, user_id)
      end
    end

    test "returns all repo roles users with actor_ids_filter" do
      assert_equal 1, @arr_org_repo.user_ids_with_privileged_access.count
      refute_includes(@arr_org_repo.user_ids_with_privileged_access, @arr_user.id)
      refute_includes(@arr_org_repo.user_ids_with_privileged_access, @arr_second_user.id)

      @arr_org.grant_org_role(assignee: @arr_user, role: @custom_org_read_role)
      @arr_org.grant_org_role(assignee: @arr_second_user, role: @custom_org_read_role)

      assert_equal 3, @arr_org_repo.user_ids_with_privileged_access.count
      assert_includes(@arr_org_repo.user_ids_with_privileged_access, @arr_user.id)
      assert_includes(@arr_org_repo.user_ids_with_privileged_access, @arr_second_user.id)

      assert_equal 1, @arr_org_repo.user_ids_with_privileged_access(actor_ids_filter: [@arr_user.id]).count
      assert_includes(@arr_org_repo.user_ids_with_privileged_access(actor_ids_filter: [@arr_user.id]), @arr_user.id)
    end

    test "returns all repo roles users with min_action provided" do
      refute_includes(@arr_org_repo.user_ids_with_privileged_access, @arr_user.id)
      @arr_org.grant_org_role(assignee: @arr_user, role: @custom_org_read_role)
      refute_includes(@arr_org_repo.user_ids_with_privileged_access(min_action: :write), @arr_user.id)
      assert_includes(@arr_org_repo.user_ids_with_privileged_access(min_action: :read), @arr_user.id)
    end

    test "returns owner and collaborators for a user-owned repo when min_action is :read" do
      repo   = create(:repository)
      owner  = repo.owner
      collab = create(:user, login: "collab")
      repo.add_member(collab)

      permission_user = create(:user, login: "permission-user")
      repo.add_vulnerability_reporter(permission_user) # any role that has the read_repo_conents permission

      unaffiliated_user = create(:user, login: "unaffiliated-user")

      assert_same_elements [owner, collab, permission_user].map(&:id), repo.user_ids_with_privileged_access(min_action: :read)
    end

    test "returns collaborators and team members for an org-owned repo when min_action is :read" do
      org = create(:organization)
      org.update_default_repository_permission(:none, actor: org.admins.first)

      org_owner = org.admins.first
      repo      = create(:repository, owner: org)
      collab    = create(:user, login: "collab")
      repo.add_member(collab)

      permission_user = create(:user, login: "permission-user")
      repo.add_vulnerability_reporter(permission_user) # any role that has the read_repo_conents permission

      team = create(:team, organization: org)
      team.add_repository(repo, :pull)

      team_member = create(:user, login: "team-member")
      org.add_member(team_member)
      team.add_member(team_member)

      org_member_without_privileged_access = create(:user, login: "org-member-without-privileged-access")
      org.add_member(org_member_without_privileged_access)

      unaffiliated_user = create(:user, login: "unaffiliated-user")

      assert_same_elements [org_owner, team_member, collab, permission_user].map(&:id), repo.user_ids_with_privileged_access(min_action: :read)
    end

    test "returns collaborators filtered by actor ids" do
      org = create(:organization)
      org.update_default_repository_permission(:none, actor: org.admins.first)

      org_owner = org.admins.first
      repo      = create(:repository, owner: org)
      collab    = create(:user, login: "collab")
      repo.add_member(collab)

      permission_user = create(:user, login: "permission-user")
      repo.add_vulnerability_reporter(permission_user) # any role that has the read_repo_conents permission

      team = create(:team, organization: org)
      team.add_repository(repo, :pull)

      team_member = create(:user, login: "team-member")
      org.add_member(team_member)
      team.add_member(team_member)

      org_member_without_privileged_access = create(:user, login: "org-member-without-privileged-access")
      org.add_member(org_member_without_privileged_access)

      unaffiliated_user = create(:user, login: "unaffiliated-user")

      user_ids = [org_owner, team_member].map(&:id)
      assert_same_elements user_ids, repo.user_ids_with_privileged_access(min_action: :read, actor_ids_filter: user_ids)
    end

    test "does not return owner if filter is provided without the owner in it" do
      repo   = create(:repository)
      owner  = repo.owner
      collab = create(:user, login: "collab")
      repo.add_member(collab)

      unaffiliated_user = create(:user, login: "unaffiliated-user")

      assert_same_elements [collab].map(&:id), repo.user_ids_with_privileged_access(min_action: :read, actor_ids_filter: [unaffiliated_user.id, collab.id])
    end

    test "returns collaborators with write access and team members with write access for an org-owned repo when min_action is :write" do
      org = create(:organization)
      org.update_default_repository_permission(:none, actor: org.admins.first)

      org_owner = org.admins.first
      repo      = create(:repository, owner: org)

      read_collab = create(:user, login: "read-collab")
      repo.add_member(read_collab, action: :read)

      write_collab = create(:user, login: "write-collab")
      repo.add_member(write_collab, action: :write)

      permission_user = create(:user, login: "permission-user")
      repo.add_vulnerability_reporter(permission_user) # any role that has the write_repo_conents permission

      read_team = create(:team, organization: org, name: "read-team")
      read_team.add_repository(repo, :pull)

      read_team_member = create(:user, login: "read-team-member")
      org.add_member(read_team_member)
      read_team.add_member(read_team_member)

      write_team = create(:team, organization: org, name: "write-team")
      write_team.add_repository(repo, :push)

      write_team_member = create(:user, login: "write-team-member")
      org.add_member(write_team_member)
      write_team.add_member(write_team_member)

      org_member_without_privileged_access = create(:user, login: "org-member-without-privileged-access")
      org.add_member(org_member_without_privileged_access)
      unaffiliated_user = create(:user, login: "unaffiliated-user")

      assert_same_elements [org_owner, write_team_member, write_collab, permission_user].map(&:id), repo.user_ids_with_privileged_access(min_action: :write)
    end

    test "min_action defaults to :read" do
      org = create(:organization)
      org.update_default_repository_permission(:none, actor: org.admins.first)

      org_owner = org.admins.first
      repo      = create(:repository, owner: org)

      read_collab = create(:user, login: "read-collab")
      repo.add_member(read_collab, action: :read)

      write_collab = create(:user, login: "write-collab")
      repo.add_member(write_collab, action: :write)

      assert_same_elements [org_owner, read_collab, write_collab].map(&:id), repo.user_ids_with_privileged_access
    end

    test "works when there's no owner" do
      repo   = create(:repository)
      collab = create(:user, login: "collab")
      repo.add_member(collab)

      # Delete owner without running callbacks
      repo.owner.delete
      repo.reload

      assert_same_elements [collab].map(&:id), repo.user_ids_with_privileged_access
    end

    test "considers users that inherit abilities on a repository from a nested team hierarchy" do
      owner = create(:user, login: "org-owner")
      org = create(:organization, admin: owner)
      org.update_default_repository_permission(:none, actor: owner)

      parent = create(:team, organization: org, privacy: :closed)
      repo = create(:repository, owner: org)
      parent.add_repository(repo, :push)

      child = create(:team, organization: org, privacy: :closed, parent_team_id: parent.id)

      team_member = create(:user, login: "team-member")
      child.add_member(team_member)

      assert_same_elements [owner, team_member].map(&:id), repo.user_ids_with_privileged_access(min_action: :write)
    end
  end

  context "#team_ids_with_direct_privileged_access" do
    test "returns teams that have direct access to repo" do
      repo = create(:repository, owner: @org)
      team = create(:team, organization: @org)
      team.add_repository(repo, :push)

      assert_same_elements [team].map(&:id), repo.team_ids_with_direct_privileged_access
    end

    test "respects min_action" do
      repo = create(:repository, owner: @org)
      team = create(:team, organization: @org)
      team.add_repository(repo, :pull)

      assert_empty repo.team_ids_with_direct_privileged_access(min_action: :write)
    end

    test "returns teams that have all repo role access" do
      repo = create(:repository, owner: @org)
      team = create(:team, organization: @org)
      @org.grant_org_role(assignee: team, role: OrganizationRole.all_repo_write_role)

      assert_same_elements [team].map(&:id), repo.team_ids_with_direct_privileged_access
    end
  end

  context "#all_repo_role_grants" do
    test "returns assignees with minimum all repo role" do
      org = @org_repo.owner

      read_user = create :user
      org.add_member read_user
      org.grant_org_role(assignee: read_user, role: OrganizationRole.all_repo_read_role)
      read_team = create :team, organization: org
      org.grant_org_role(assignee: read_team, role: OrganizationRole.all_repo_read_role)

      write_user = create :user
      org.add_member write_user
      org.grant_org_role(assignee: write_user, role: OrganizationRole.all_repo_write_role)
      write_team = create :team, organization: org
      org.grant_org_role(assignee: write_team, role: OrganizationRole.all_repo_write_role)

      admin_user = create :user
      org.add_member admin_user
      org.grant_org_role(assignee: admin_user, role: OrganizationRole.all_repo_admin_role)
      admin_team = create :team, organization: org
      org.grant_org_role(assignee: admin_team, role: OrganizationRole.all_repo_admin_role)

      # missing min_action should return all assignees
      grantees = @org_repo.all_repo_role_grants
      assert_same_elements [read_user.id, write_user.id, admin_user.id], grantees["User"]
      assert_same_elements [read_team.id, write_team.id, admin_team.id], grantees["Team"]

      # read min_action should return all assignees
      grantees = @org_repo.all_repo_role_grants(:read)
      assert_same_elements [read_user.id, write_user.id, admin_user.id], grantees["User"]
      assert_same_elements [read_team.id, write_team.id, admin_team.id], grantees["Team"]

      # write min_action should return assignees with write and admin
      grantees = @org_repo.all_repo_role_grants(:write)
      assert_same_elements [write_user.id, admin_user.id], grantees["User"]
      assert_same_elements [write_team.id, admin_team.id], grantees["Team"]

      # admin min_action should return assignees with admin only
      grantees = @org_repo.all_repo_role_grants(:admin)
      assert_same_elements [admin_user.id], grantees["User"]
      assert_same_elements [admin_team.id], grantees["Team"]
    end
  end

  context "#user_ids_with_all_repo_role_grants" do
    test "returns direct user assignees" do
      org = @org_repo.owner
      read_user = create :user
      org.add_member(read_user)
      write_user = create :user
      org.add_member(write_user)

      assert_predicate org.grant_org_role(assignee: read_user, role: OrganizationRole.all_repo_read_role), :success?
      assert_predicate org.grant_org_role(assignee: write_user, role: OrganizationRole.all_repo_write_role), :success?

      assert_same_elements [write_user.id], @org_repo.user_ids_with_all_repo_role_grants(min_action: :write)
      assert_same_elements [read_user.id, write_user.id], @org_repo.user_ids_with_all_repo_role_grants(min_action: :read)
    end

    test "includes direct and indirect user assignees" do
      org = @org_repo.owner
      read_user = create :user
      org.add_member(read_user)
      team = create(:team, privacy: :closed, organization: org)
      team_member = create :user
      team.add_member team_member
      org.add_member(team_member)

      assert_predicate org.grant_org_role(assignee: read_user, role: OrganizationRole.all_repo_read_role), :success?
      assert_predicate org.grant_org_role(assignee: team, role: OrganizationRole.all_repo_read_role), :success?

      assert_same_elements [read_user.id, team_member.id], @org_repo.user_ids_with_all_repo_role_grants
    end

    test "respects include_child_teams" do
      org = @org_repo.owner
      parent_team = create(:team, privacy: :closed, organization: org)
      child_team = create(:team, privacy: :closed, organization: org, parent_team_id: parent_team.id)

      parent_team_member = create :user
      org.add_member(parent_team_member)
      parent_team.add_member(parent_team_member)

      child_team_member = create :user
      org.add_member(child_team_member)
      child_team.add_member(child_team_member)

      org.grant_org_role(assignee: parent_team, role: OrganizationRole.all_repo_read_role)

      assert_same_elements [parent_team_member.id], @org_repo.user_ids_with_all_repo_role_grants(include_child_teams: false)
      assert_same_elements [parent_team_member.id, child_team_member.id], @org_repo.user_ids_with_all_repo_role_grants(include_child_teams: true)
    end
  end

  context "direct_org_member_ids" do
    test "shows org members with direct access to a repository" do
      skip if TestEnv.all_repo_roles_test? # direct_org_member_ids should not include all-repo roles

      direct_user = create :user
      @org_on_business_plus.add_member(direct_user)
      @org_repo.add_member(direct_user)

      direct_org_member_ids = @org_repo.direct_org_member_ids
      refute_includes direct_org_member_ids, @maintain_user.id
      assert_equal [direct_user.id], direct_org_member_ids
    end

    test "filters org direct members by action" do
      skip if TestEnv.all_repo_roles_test? # direct_org_member_ids should not include all-repo roles

      direct_user_read = create :user
      direct_user_triage = create :user
      direct_user_admin = create :user
      @org_on_business_plus.add_member(direct_user_read)
      @org_on_business_plus.add_member(direct_user_triage)
      @org_on_business_plus.add_member(direct_user_admin)

      outside_collaborator_read = create :user
      outside_collaborator_triage = create :user
      outside_collaborator_admin = create :user
      @org_repo.add_member(outside_collaborator_read, action: :read)
      @org_repo.add_member(outside_collaborator_triage, action: :triage)
      @org_repo.add_member(outside_collaborator_admin, action: :admin)
      @org_repo.add_member(direct_user_read, action: :read)
      @org_repo.add_member(direct_user_triage, action: :triage)
      @org_repo.add_member(direct_user_admin, action: :admin)

      # For each of the following, only the direct member with the appropriate
      # permission should be returned
      assert_equal [direct_user_read.id], @org_repo.direct_org_member_ids(action: :read)
      assert_equal [direct_user_triage.id], @org_repo.direct_org_member_ids(action: :triage)
      assert_equal [direct_user_admin.id], @org_repo.direct_org_member_ids(action: :admin)
    end

    test "filters org direct members by actor_id" do
      skip if TestEnv.all_repo_roles_test? # direct_org_member_ids should not include all-repo roles

      direct_user1 = create :user
      direct_user2 = create :user
      @org_on_business_plus.add_member(direct_user1)
      @org_on_business_plus.add_member(direct_user2)
      @org_repo.add_member(direct_user1, action: :read)
      @org_repo.add_member(direct_user2, action: :read)

      direct_member_ids = @org_repo.direct_org_member_ids(actor_ids: [direct_user1.id])
      refute_includes direct_member_ids, direct_user2
      assert_equal [direct_user1.id], direct_member_ids
    end

    test "returns empty results for a user owned repository" do
      collab_user = create :user
      @user_repo.add_member(collab_user)

      direct_member_ids = @user_repo.direct_org_member_ids
      refute_includes direct_member_ids, @repo_owner
      refute_includes direct_member_ids, collab_user
      assert_empty @user_repo.direct_org_member_ids
    end
  end

  context "outside_collaborator_member_ids" do
    test "shows outside collaborators on an org owned repository" do
      repo = create(:repository, owner: @org)
      direct_user = create :user
      collab_user = create :user
      @org.add_member(direct_user)
      repo.add_member(direct_user)
      repo.add_member(collab_user)

      outside_collaborator_ids = repo.outside_collaborator_member_ids
      refute_includes outside_collaborator_ids, direct_user
      assert_equal [collab_user.id], outside_collaborator_ids
    end

    test "filters outside collaborators by action" do
      repo = create(:repository, owner: @org_on_business_plus)
      direct_user_read = create :user
      direct_user_triage = create :user
      direct_user_admin = create :user
      @org_on_business_plus.add_member(direct_user_read)
      @org_on_business_plus.add_member(direct_user_triage)
      @org_on_business_plus.add_member(direct_user_admin)

      outside_collaborator_read = create :user
      outside_collaborator_triage = create :user
      outside_collaborator_admin = create :user
      repo.add_member(outside_collaborator_read, action: :read)
      repo.add_member(outside_collaborator_triage, action: :triage)
      repo.add_member(outside_collaborator_admin, action: :admin)
      repo.add_member(direct_user_read, action: :read)
      repo.add_member(direct_user_triage, action: :triage)
      repo.add_member(direct_user_admin, action: :admin)

      # For each of the following, only the outside collaborator  with the appropriate
      # permission should be returned
      assert_equal [outside_collaborator_read.id], repo.outside_collaborator_member_ids(action: :read)
      assert_equal [outside_collaborator_triage.id], repo.outside_collaborator_member_ids(action: :triage)
      assert_equal [outside_collaborator_admin.id], repo.outside_collaborator_member_ids(action: :admin)
    end

    test "filters outside collaborators by actor_id" do
      repo = create(:repository, owner: @org)
      outside_collaborator1 = create :user
      outside_collaborator2 = create :user

      repo.add_member(outside_collaborator1, action: :read)
      repo.add_member(outside_collaborator2, action: :read)

      outside_collaborator_ids = repo.outside_collaborator_member_ids(actor_ids: [outside_collaborator2.id])
      refute_includes outside_collaborator_ids, outside_collaborator1
      assert_equal [outside_collaborator2.id], outside_collaborator_ids
    end

    test "returns all outside collaborators for a user owned repository" do
      collab_user = create :user
      @user_repo.add_member(collab_user)

      user_repo_outside_collaborator_ids = @user_repo.outside_collaborator_member_ids
      refute_includes user_repo_outside_collaborator_ids, @repo_owner
      assert_equal [collab_user.id], user_repo_outside_collaborator_ids
    end
  end

  context "async_has_access?" do
    test "returns true when the viewer is the repository owner" do
      repo = create(:repository)
      assert repo.async_has_access?(repo.owner).sync
    end

    test "returns true when the viewer is a repository member" do
      repo = create(:repository)
      member = create(:user)
      repo.add_member(member)

      assert repo.async_has_access?(member).sync
    end

    test "returns true when the viewer is a member of the repository's org" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      member = create(:user)
      org.add_member(member)

      assert repo.async_has_access?(member).sync
    end

    test "returns false for randos" do
      repo = create(:repository)
      refute repo.async_has_access?(create(:user)).sync
    end
  end

  context "#owning_organization_id" do
    test "returns nil for forks of org-owned public repos owned by a user" do
      forked = create(:fork_repository, forker: @forker, fork_repo: @org_repo)

      assert_nil forked.owning_organization_id
      assert_nil forked.async_owning_organization_id.sync
    end

    test "returns owner org id for forks of org-owned public repos owned by an org" do
      forked = create(:fork_repository, forker: @forker, fork_repo: @org_repo, organization: @other_org)

      assert_equal forked.owning_organization_id, @other_org.id
      assert_equal forked.async_owning_organization_id.sync, @other_org.id
    end

    test "returns nil for forks of user-owned public repos owned by a user" do
      forked = create(:fork_repository, forker: @forker, fork_repo: @user_repo)

      assert_nil forked.owning_organization_id
      assert_nil forked.async_owning_organization_id.sync
    end

    test "returns owner org id for forks of user-owned public repos owned by an org" do
      forked = create(:fork_repository, forker: @forker, fork_repo: @user_repo, organization: @other_org)

      assert_equal forked.owning_organization_id, @other_org.id
      assert_equal forked.async_owning_organization_id.sync, @other_org.id
    end

    test "returns parent org id for forks of org-owned private repos owned by a user" do
      forked = create(:fork_repository, forker: @forker, fork_repo: @org_private_repo)

      assert_equal forked.owning_organization_id, @org_on_business_plus.id
      assert_equal forked.async_owning_organization_id.sync, @org_on_business_plus.id
    end

    test "returns owner org id for forks of org-owned private repos owned by an org" do
      forked = create(:fork_repository, forker: @forker, fork_repo: @org_private_repo, organization: @other_org)

      assert_equal forked.owning_organization_id, @other_org.id
      assert_equal forked.async_owning_organization_id.sync, @other_org.id
    end

    test "returns owner org id for forks of user-owned private repos owned by an org" do
      forked = create(:fork_repository, forker: @forker, fork_repo: @user_private_repo, organization: @other_org)

      assert_equal forked.owning_organization_id, @other_org.id
      assert_equal forked.async_owning_organization_id.sync, @other_org.id
    end

    test "returns nil for forks of user-owned private repos owned by a user" do
      forked = create(:fork_repository, forker: @forker, fork_repo: @user_private_repo)

      assert_nil forked.owning_organization_id
      assert_nil forked.async_owning_organization_id.sync
    end

    test "returns nil for repo with user owner" do
      assert_nil @user_repo.owning_organization_id
      assert_nil @user_repo.async_owning_organization_id.sync
    end

    test "returns owner org id for org-owned repos" do
      assert_equal @org_repo.owning_organization_id, @org_on_business_plus.id
      assert_equal @org_repo.async_owning_organization_id.sync, @org_on_business_plus.id
    end

    test "returns owner org id from owner if organization_id is not populated" do
      @org_repo.update!(organization_id: nil)

      assert_equal @org_repo.owning_organization_id, @org_on_business_plus.id
      assert_equal @org_repo.async_owning_organization_id.sync, @org_on_business_plus.id
    end

    test "returns nil for forks of org-owned public repo which is deleted" do
      forked = create(:fork_repository, forker: @forker, fork_repo: @org_repo)
      @org_repo.destroy
      forked.reload # clear association cache containing now deleted parent

      assert_nil forked.owning_organization_id
      assert_nil forked.async_owning_organization_id.sync
    end

    test "returns nil for fork of user-owned public repo with deleted owner" do
      forked = create(:fork_repository, forker: @forker, fork_repo: @user_repo)
      @user_repo.destroy
      forked.reload # clear association cache containing now deleted parent

      assert_nil forked.owning_organization_id
      assert_nil forked.async_owning_organization_id.sync
    end
  end

  context "#direct_role_for" do
    test "returns nil if org-member does not have direct access" do
      @org_on_business_plus.add_member(@other_user)
      assert_nil @org_repo.direct_role_for(@other_user)
    end

    test "returns nil if collaborator does not have direct access" do
      assert_nil @org_repo.direct_role_for(@other_user)
      assert_nil @user_repo.direct_role_for(@other_user)
    end

    test "returns nil if team does not have direct access" do
      assert_nil @org_repo.direct_role_for(@team)
    end

    test "returns nil if nested team does not have direct access" do
      @team.add_repository(@org_repo, :push)

      assert_equal :write, @org_repo.direct_role_for(@team)
      assert_nil @org_repo.direct_role_for(@child_team)
    end

    test "returns direct role for org-member" do
      skip if TestEnv.all_repo_roles_test? # direct_role_for should not consider all-repo roles

      @org_on_business_plus.add_member(@other_user)

      # grant direct access to the repo
      @org_repo.add_member(@other_user, action: :write)

      # grant higher access to the repo via teams
      @team.add_member(@maintain_user)
      @team.add_repository(@org_repo, :admin)

      assert_equal :write, @org_repo.direct_role_for(@other_user)
    end

    test "returns direct role for outside collab" do
      # grant direct access to the repo
      @org_repo.add_member(@other_user, action: :maintain)
      assert_equal :maintain, @org_repo.direct_role_for(@other_user)
    end

    test "returns direct role for user-owned repo" do
      # note that user owned repos only grant :write
      @user_repo.add_member(@other_user)
      assert_equal :write, @user_repo.direct_role_for(@other_user)
    end

    test "returns direct role for team" do
      @team.add_repository(@org_repo, :push)
      @child_team.add_repository(@org_repo, :triage)

      assert_equal :write, @org_repo.direct_role_for(@team)
      assert_equal :triage, @org_repo.direct_role_for(@child_team)
    end

    test "returns role if parent does not have direct access but nested team does" do
      @child_team.add_repository(@org_repo, :triage)

      assert_nil @org_repo.direct_role_for(@team)
      assert_equal :triage, @org_repo.direct_role_for(@child_team)
    end
  end

  context "#direct_roles_for" do
    test "returns empty Hash when no actors are passed" do
      expected_result = {}
      assert_equal expected_result, @user_repo.direct_roles_for(nil)
      assert_equal expected_result, @user_repo.direct_roles_for([])
    end

    test "calculates direct access for Users" do
      skip if TestEnv.all_repo_roles_test? # direct_roles_for should not consider all-repo roles

      # org member
      @org_on_business_plus.add_member(@other_user)
      @org_repo.add_member(@other_user, action: :write)

      # outide collaborator
      triage_user = create(:user)
      @org_repo.add_member(triage_user, action: :triage)

      # user without direct access
      unknown_user = create(:user)

      expected_result = { triage_user => :triage, @other_user => :write }

      assert_equal expected_result, @org_repo.direct_roles_for([triage_user, @other_user, unknown_user], actor_type: "User")
    end

    test "calculates direct access for Teams" do
      @team.add_repository(@org_repo, :admin)
      expected_result = { @team => :admin }

      assert_equal expected_result, @org_repo.direct_roles_for([@team, @child_team])
    end
  end

  context "self.permission_to_action" do
    test "returns proper action for system permissions" do
      %i(read triage write maintain admin).each do |permission|
        assert_equal permission, Repository.permission_to_action(permission)
        assert_equal permission, Repository.permission_to_action(permission.to_s)
      end
    end

    test "returns proper action for legacy permissions" do
      assert_equal :read, Repository.permission_to_action(:pull)
      assert_equal :read, Repository.permission_to_action("pull")

      assert_equal :write, Repository.permission_to_action(:push)
      assert_equal :write, Repository.permission_to_action("push")
    end

    test "case insensitive and strips" do
      assert_equal :admin, Repository.permission_to_action("  AdMiN ")
    end

    test "errors when an invalid permission is passed" do
      assert_raises(ArgumentError) { Repository.permission_to_action(nil) }
      assert_raises(ArgumentError) { Repository.permission_to_action("invalid") }
    end
  end

  context "#org_with_default_permission_owner?" do
    test "returns false when owner is blank" do
      repo = build(:repository, owner: nil)

      refute_predicate repo, :org_with_default_permission_owner?
    end

    test "returns false when owner is not an organization" do
      user = build(:user)
      repo = build(:repository, owner: user)

      refute_predicate repo, :org_with_default_permission_owner?
    end

    test "returns false when org owner does not have default repository permission" do
      org = create(:organization)
      only = [RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
      perform_enqueued_jobs(only: only) { org.update_default_repository_permission(:none, actor: org.admins.first) }
      repo = build(:repository, owner: org)

      refute_predicate repo, :org_with_default_permission_owner?
    end

    test "returns true when owner is an organization with a default repository permission" do
      org = create(:organization)
      repo = build(:repository, owner: org)

      assert_predicate repo, :org_with_default_permission_owner?
    end
  end

  context "#cannot_invite_outside_collaborators?" do
    test "returns false for org owner if disallow_members_can_invite_outside_collaborators is set" do
      owner = create(:user)
      @org_on_business_plus.add_member(owner, action: :admin)

      @org_on_business_plus.disallow_members_can_invite_outside_collaborators(actor: owner, force: true)
      assert_equal @org_on_business_plus.business, @business

      refute @org_repo.cannot_invite_outside_collaborators?(owner)
    end

    test "returns true for org owner if enterprise_admins_only_can_invite_outside_collaborators is set" do
      owner = create(:user)
      @org_on_business_plus.add_member(owner, action: :admin)

      @business.enterprise_admins_only_can_invite_outside_collaborators(actor: owner)

      assert @org_repo.reload.cannot_invite_outside_collaborators?(owner)
    end

    test "returns false for a business owner if enterprise_admins_only_can_invite_outside_collaborators is set" do
      owner = @business.admins.first

      @business.enterprise_admins_only_can_invite_outside_collaborators(actor: owner)
      @org_on_business_plus.add_member(owner, action: :admin)

      refute @org_repo.reload.cannot_invite_outside_collaborators?(owner)
    end

    test "returns true for org member if disallow_members_can_invite_outside_collaborators is set" do
      owner, member = create(:user), create(:user)
      org = create(:business_plus_organization, login: "ghec", admin: owner)
      repo = create(:repository, owner: org)
      org.add_member(member)
      repo.add_member(member, action: :admin)

      org.disallow_members_can_invite_outside_collaborators(actor: owner, force: true)

      assert repo.cannot_invite_outside_collaborators?(member)
    end
  end

  context "#can_see_deployments?" do
    test "returns false when there is no user" do
      repo = create(:repository)
      create(:deployment, repository: repo)

      refute repo.can_see_deployments?(nil)
    end

    test "returns false when there aren't any deployments" do
      owner = create(:user)
      repo = create(:repository, owner: owner)

      refute repo.can_see_deployments?(owner)
    end

    test "returns true when user can't write to repo and there are deployments" do
      owner, other_user = create(:user), create(:user)
      repo = create(:repository, owner: owner)
      create(:deployment, repository: repo)

      assert repo.can_see_deployments?(other_user)
    end

    test "returns true when user can write to repo and there are deployments" do
      owner = create(:user)
      repo = create(:repository, owner: owner)
      create(:deployment, repository: repo)

      assert repo.can_see_deployments?(owner)
    end
  end

  context "multiple_target_for_conditional_access" do
    test "computes TFCA for multiple repositories" do
      result = Repository.multiple_target_for_conditional_access([@grit, @ambition, @simple, @facebox, @internal])
      expected = { @grit => @mojombo, @ambition => @defunkt, @simple => @defunkt, @facebox => @defunkt, @internal => @org }
      assert_equal expected, result
    end

    test "raises if repositories are not provided" do
      assert_raises ArgumentError do
        Repository.multiple_target_for_conditional_access([@defunkt, @org])
      end
      assert_raises ArgumentError do
        Repository.multiple_target_for_conditional_access(Organization.all)
      end
    end

    test "doesn't re-query for tfca if it's already loaded" do
      @grit.owner

      assert_query_count(0) do
        Repository.multiple_target_for_conditional_access([@grit])
      end
    end

    test "batches a single query for tfcas if they're not already loaded" do
      @grit.reload
      @ambition.reload

      assert_query_count(1, ignore_feature_flags: true) do
        Repository.multiple_target_for_conditional_access([@grit, @ambition])
      end
    end
  end

  context "permission cache" do
    test "preload_repository_permissions caches results" do
      org_admin = @org_on_business_plus.admins.first
      PermissionCache.enable do
        Repository.preload_repository_permissions(repositories: [@org_repo], users: [org_admin, @maintain_user])

        GitHub::MysqlInstrumenter.reset_stats
        GitHub::MysqlInstrumenter.with_track do
          cached_result = Authorization.service.most_capable_ability_between(actor: org_admin, subject: @org_repo)
          assert_equal 0, GitHub::MysqlInstrumenter.query_count
          assert_predicate cached_result, :admin?
        end
      end
    end

    test "preload_repository_permissions batches correctly" do
      default_batch_cache_entries = []
      small_batch_cache_entries = []

      PermissionCache.enable do
        Repository.preload_repository_permissions(repositories: [@ambition, @facebox, @grit], users: [@defunkt])
        PermissionCache.each do |cache_entry|
          default_batch_cache_entries << cache_entry
        end
      end

      Repository::AbilityDependency.stub_const(:PRELOAD_BATCH_SIZE, 2) do
        PermissionCache.enable do
          Repository.preload_repository_permissions(repositories: [@ambition, @facebox, @grit], users: [@defunkt])
          PermissionCache.each do |cache_entry|
            small_batch_cache_entries << cache_entry
          end
        end
      end

      assert_same_elements default_batch_cache_entries, small_batch_cache_entries
    end
  end

  context "#available_assignee_ids" do
    test "limits the number of assignable users when limit is passed" do
      result = @org_repo.available_assignee_ids(limit: 1)

      assert_equal 1, result.size
    end

    test "returns all assignable users when :limit is not passed" do
      result = @org_repo.available_assignee_ids

      assert result.size > 1
    end
  end

end

class EmuRepositoryAbilityDependencyTest < GitHub::TestCase
  fixtures do
    @non_emu = create(:user)

    @admin = create(:emu, :owner)
    @business = @admin.enterprise_managed_business

    @org = create(:organization, business: @business, admin: @admin)

    @member = create :emu, business: @business

    @org.add_member(@member, action: :write)

    @org_repo = create :repository, owner: @org
  end

  context "#cannot_invite_outside_collaborators?" do
    test "returns true for org owner if disallow_members_can_invite_outside_collaborators is set" do
      @org.disallow_members_can_invite_outside_collaborators(actor: @admin, force: true)

      assert @org_repo.cannot_invite_outside_collaborators?(@admin)
    end

    test "returns true for org member if disallow_members_can_invite_outside_collaborators is set" do
      @org.disallow_members_can_invite_outside_collaborators(actor: @admin, force: true)

      assert @org_repo.cannot_invite_outside_collaborators?(@member)
    end

    test "returns true for org owner if disallow_members_can_invite_outside_collaborators is not set" do
      @org.disallow_members_can_invite_outside_collaborators(actor: @admin, force: false)

      assert @org_repo.cannot_invite_outside_collaborators?(@admin)
    end

    test "returns true for org member if disallow_members_can_invite_outside_collaborators is not set" do
      @org.disallow_members_can_invite_outside_collaborators(actor: @admin, force: true)

      assert @org_repo.cannot_invite_outside_collaborators?(@member)
    end
  end
end unless GitHub.single_business_environment?
