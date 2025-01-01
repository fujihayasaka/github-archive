# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationRepositoryPermissionsTest < GitHub::TestCase
  fixtures do
    @org_admin = create(:user, login: "org-admin")
    @org       = create(:organization, admin: @org_admin)
    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:none, actor: @org_admin) }
    @org.allow_private_repository_forking(actor: @org_admin)

    @repo = create(:private_repository, owner: @org)
    @user = create(:user, plan: "small")
    @team = create(:team, organization: @org)
    @team.add_member(@user)
  end

  context "initialize" do
    test "works for an org-owned repo" do
      refute_nil Organization::RepositoryPermissions.new(@repo, @user)
    end

    test "works for a fork of an org-owned repo" do
      forker = create(:user, login: "forker")
      @org.add_admin(forker)
      fork, status = @repo.fork(forker: forker)
      assert_equal :created, status

      refute_nil Organization::RepositoryPermissions.new(fork, @user)
    end

    test "blows up for a user-owned non-fork repo" do
      user_repo = create(:private_repository, :minimal, owner: @user)

      assert_raises ArgumentError do
        Organization::RepositoryPermissions.new(user_repo, @user)
      end
    end
  end

  context "active_permission" do
    test "returns the highest permission when it's granted by a team" do
      @repo.add_member(@user, action: :write)
      @team.add_repository(@repo, :admin)

      access = Organization::RepositoryPermissions.new(@repo, @user)

      assert_equal :admin, access.active_permission
    end

    test "returns the highest permission when it's granted by the org's default repository permission" do
      @org.add_member(@user)
      @repo.add_member(@user, action: :read)
      @team.add_repository(@repo, :push)
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:admin, actor: @org_admin) }

      access = Organization::RepositoryPermissions.new(@repo, @user)

      assert_equal :admin, access.active_permission
    end

    test "returns the highest permission when it's granted directly" do
      @repo.add_member(@user, action: :admin)
      @team.add_repository(@repo, :push)

      access = Organization::RepositoryPermissions.new(@repo, @user)

      assert_equal :admin, access.active_permission
    end

    test "returns nil when the user has no access to the repo" do
      access = Organization::RepositoryPermissions.new(@repo, @user)
      assert_nil access.active_permission
    end
  end

  context "active_abilities" do
    test "returns the abilities that grant the active permission" do
      @org.add_member(@user)
      @repo.add_member(@user, action: :admin)
      @team.add_repository(@repo, :admin)
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:admin, actor: @org_admin) }

      write_team = create(:team, organization: @org, name: "write-team")
      write_team.add_member(@user)
      write_team.add_repository(@repo, :push)

      access = Organization::RepositoryPermissions.new(@repo, @user)

      assert_same_elements [@user, @team, @org], access.active_abilities.map(&:actor)
    end

    test "returns abilities from teams that inherit active permission" do
      user = create(:user, plan: "small")
      parent_team = create(:team, organization: @org, privacy: :closed)
      child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: parent_team.id)
      parent_team.add_repository(@repo, :admin)
      child_team.add_member(user)

      @org.update_default_repository_permission(:none, actor: @org_admin)

      access = Organization::RepositoryPermissions.new(@repo, user)

      assert_same_elements [child_team], access.active_abilities.map(&:actor)
    end

    test "returns abilities from teams for direct and inherited active permission" do
      user = create(:user, plan: "small")
      parent_team = create(:team, organization: @org, privacy: :closed)
      child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: parent_team.id)
      grandchild_team = create(:team, organization: @org, privacy: :closed, parent_team_id: child_team.id)
      parent_team.add_repository(@repo, :admin)
      child_team.add_member(user)
      parent_team.add_member(user)
      grandchild_team.add_member(user)

      @org.update_default_repository_permission(:none, actor: @org_admin)

      access = Organization::RepositoryPermissions.new(@repo, user)

      assert_same_elements [parent_team, child_team, grandchild_team], access.active_abilities.map(&:actor)
    end

    test "returns unique memberships when a team has multiple ability records on a repo" do
      user = create(:user, plan: "small")
      parent_team = create(:team, organization: @org, privacy: :closed)
      child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: parent_team.id)
      grandchild_team = create(:team, organization: @org, privacy: :closed, parent_team_id: child_team.id)
      parent_team.add_repository(@repo, :admin)
      child_team.add_repository(@repo, :admin)
      grandchild_team.add_member(user)

      @org.update_default_repository_permission(:none, actor: @org_admin)

      access = Organization::RepositoryPermissions.new(@repo, user)

      assert_same_elements [grandchild_team], access.active_abilities.map(&:actor)
    end

    test "returns most capable permission when a team has multiple ability records with different permission on a repo" do
      user = create(:user, plan: "small")
      parent_team = create(:team, organization: @org, privacy: :closed)
      child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: parent_team.id)
      grandchild_team = create(:team, organization: @org, privacy: :closed, parent_team_id: child_team.id)
      child_team.add_repository(@repo, :read)
      parent_team.add_repository(@repo, :admin)
      grandchild_team.add_member(user)

      @org.update_default_repository_permission(:none, actor: @org_admin)

      access = Organization::RepositoryPermissions.new(@repo, user)

      assert_same_elements [grandchild_team], access.active_abilities.map(&:actor)
      assert_equal ["admin"], access.active_abilities.map(&:action)
    end

    test "excludes the default repository permission for an outside collaborator" do
      outside_collaborator = create(:user, login: "outside-collaborator")
      @repo.add_member(outside_collaborator, action: :admin)
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:admin, actor: @org_admin) }

      access = Organization::RepositoryPermissions.new(@repo, outside_collaborator)

      assert_same_elements [outside_collaborator], access.active_abilities.map(&:actor)
    end

    test "can exclude team abilities" do
      @repo.add_member(@user, action: :admin)
      @team.add_repository(@repo, :push)

      access = Organization::RepositoryPermissions.new(@repo, @user)

      assert_same_elements [@user], access.active_abilities.map(&:actor)
    end

    test "can exclude direct abilities" do
      @team.add_repository(@repo, :admin)
      @repo.add_member(@user, action: :write)

      access = Organization::RepositoryPermissions.new(@repo, @user)

      assert_same_elements [@team], access.active_abilities.map(&:actor)
    end

    test "can exclude the organization's default repository permission" do
      @org.add_member(@user)
      @team.add_repository(@repo, :admin)
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:write, actor: @org_admin) }

      access = Organization::RepositoryPermissions.new(@repo, @user)

      assert_same_elements [@team], access.active_abilities.map(&:actor)
    end
  end

  context "direct_ability_active?" do
    test "returns true if the user's direct ability on the repo is active" do
      @repo.add_member(@user, action: :admin)

      assert Organization::RepositoryPermissions.new(@repo, @user).direct_ability_active?
    end

    test "returns false if the user's direct ability on the repo is inactive" do
      @team.add_repository(@repo, :admin)
      @repo.add_member(@user, action: :write)

      refute Organization::RepositoryPermissions.new(@repo, @user).direct_ability_active?
    end

    test "returns false if the user has no direct ability on the repo" do
      @team.add_repository(@repo, :admin)

      refute Organization::RepositoryPermissions.new(@repo, @user).direct_ability_active?
    end
  end

  context "inactive_abilities" do
    test "returns the abilities that are below the active permission" do
      admin_team = create(:team, organization: @org, name: "admin-team")
      admin_team.add_member(@user)
      admin_team.add_repository(@repo, :admin)

      @org.add_member(@user)
      @repo.add_member(@user, action: :read)
      @team.add_repository(@repo, :push)
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:read, actor: @org_admin) }

      access = Organization::RepositoryPermissions.new(@repo, @user)

      assert_same_elements [@user, @team, @org], access.inactive_abilities.map(&:actor)
    end

    test "excludes team abilities if they all grant the active permission" do
      @team.add_repository(@repo, :admin)
      @repo.add_member(@user, action: :write)

      access = Organization::RepositoryPermissions.new(@repo, @user)

      assert_same_elements [@user], access.inactive_abilities.map(&:actor)
    end

    test "excludes the direct user ability if it grants the active permission" do
      @repo.add_member(@user, action: :admin)
      @team.add_repository(@repo, :push)

      access = Organization::RepositoryPermissions.new(@repo, @user)

      assert_same_elements [@team], access.inactive_abilities.map(&:actor)
    end

    test "excludes the organization's default repository permission if it grants the active permission" do
      @org.add_member(@user)
      @team.add_repository(@repo, :push)
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:admin, actor: @org_admin) }

      access = Organization::RepositoryPermissions.new(@repo, @user)

      assert_same_elements [@team], access.inactive_abilities.map(&:actor)
    end
  end

  context "revoke_all" do
    test "destroys direct repo permission and removes the user from all teams with access to the repo" do
      @repo.add_member(@user, action: :admin)
      @team.add_repository(@repo, :admin)

      write_team = create(:team, organization: @org, name: "write-team")
      write_team.add_member(@user)
      write_team.add_repository(@repo, :push)

      assert @repo.adminable_by?(@user)

      Organization::RepositoryPermissions.new(@repo, @user).revoke_all(actor: @org_admin)

      refute @repo.pullable_by?(@user)
      refute @team.member?(@user)
      refute write_team.member?(@user)
    end

    test "works when there are only team permissions" do
      @team.add_repository(@repo, :admin)

      write_team = create(:team, organization: @org, name: "write-team")
      write_team.add_member(@user)
      write_team.add_repository(@repo, :push)

      Organization::RepositoryPermissions.new(@repo, @user).revoke_all(actor: @org_admin)

      refute @repo.pullable_by?(@user)
      refute @team.member?(@user)
      refute write_team.member?(@user)
    end

    test "works when there is only a direct permission" do
      @repo.add_member(@user, action: :admin)

      Organization::RepositoryPermissions.new(@repo, @user).revoke_all(actor: @org_admin)

      refute @repo.pullable_by?(@user)
    end

    test "instruments an event with an actor specified" do
      events = subscribe "repo.remove_member"
      @repo.add_member(@user, action: :admin)

      Organization::RepositoryPermissions.new(@repo, @user).revoke_all(actor: @org_admin)

      expected_payload = {
        visibility: @repo.visibility.to_sym,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: false,
        org: @org.login,
        org_id: @org.id,
        fork_source: @repo.nwo,
        fork_source_id: @repo.id,
        user: @user.login,
        user_id: @user.id,
        actor: @org_admin.login,
        actor_id: @org_admin.id,
      }

      assert event = events.pop, "No event was created."
      assert_equal "repo.remove_member", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments an event with the default actor if not specified" do
      events = subscribe "repo.remove_member"
      @repo.add_member(@user, action: :admin)

      Organization::RepositoryPermissions.new(@repo, @user).revoke_all

      expected_payload = {
        visibility: @repo.visibility.to_sym,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: false,
        org: @org.login,
        org_id: @org.id,
        fork_source: @repo.nwo,
        fork_source_id: @repo.id,
        user: @user.login,
        user_id: @user.id,
        actor: @org.login,
        actor_id: @org.id,
      }

      assert event = events.pop, "No event was created."
      assert_equal "repo.remove_member", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "revoke_active" do
    test "destroys direct repo permission and removes the user from teams granting the active permission to the repo" do
      @repo.add_member(@user, action: :admin)
      @team.add_repository(@repo, :admin)

      write_team = create(:team, organization: @org, name: "write-team")
      write_team.add_member(@user)
      write_team.add_repository(@repo, :push)

      assert @repo.adminable_by?(@user)

      Organization::RepositoryPermissions.new(@repo, @user).revoke_active(actor: @org_admin)

      refute @repo.adminable_by?(@user)
      refute @team.member?(@user)
      assert @repo.pushable_by?(@user)
      assert write_team.member?(@user)
    end

    test "works when the only active permissions are team permissions" do
      @team.add_repository(@repo, :admin)

      write_team = create(:team, organization: @org, name: "write-team")
      write_team.add_member(@user)
      write_team.add_repository(@repo, :push)

      Organization::RepositoryPermissions.new(@repo, @user).revoke_active(actor: @org_admin)

      refute @repo.adminable_by?(@user)
      assert @repo.pushable_by?(@user)
    end

    test "works when the only active permission is a direct permission" do
      @repo.add_member(@user, action: :admin)
      @team.add_repository(@repo, :push)

      assert @repo.adminable_by?(@user)

      Organization::RepositoryPermissions.new(@repo, @user).revoke_active(actor: @org_admin)

      refute @repo.adminable_by?(@user)
      assert @repo.pushable_by?(@user)
    end

    test "works when the only inactive permission is a direct permission" do
      @team.add_repository(@repo, :admin)
      @repo.add_member(@user, action: :write)

      assert @repo.adminable_by?(@user)

      Organization::RepositoryPermissions.new(@repo, @user).revoke_active(actor: @org_admin)

      refute @repo.adminable_by?(@user)
      assert @repo.pushable_by?(@user)
    end

    test "works when there are no inactive permissions" do
      @repo.add_member(@user, action: :admin)
      @team.add_repository(@repo, :admin)

      assert @repo.adminable_by?(@user)

      Organization::RepositoryPermissions.new(@repo, @user).revoke_active(actor: @org_admin)

      refute @repo.pullable_by?(@user)
    end

    test "instruments an event with an actor specified" do
      events = subscribe "repo.remove_member"
      @repo.add_member(@user, action: :admin)

      Organization::RepositoryPermissions.new(@repo, @user).revoke_active(actor: @org_admin)

      expected_payload = {
        visibility: @repo.visibility.to_sym,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: false,
        org: @org.login,
        org_id: @org.id,
        fork_source: @repo.nwo,
        fork_source_id: @repo.id,
        user: @user.login,
        user_id: @user.id,
        actor: @org_admin.login,
        actor_id: @org_admin.id,
      }

      assert event = events.pop, "No event was created."
      assert_equal "repo.remove_member", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments an event with the default actor if not specified" do
      events = subscribe "repo.remove_member"
      @repo.add_member(@user, action: :admin)

      Organization::RepositoryPermissions.new(@repo, @user).revoke_active

      expected_payload = {
        visibility: @repo.visibility.to_sym,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: false,
        org: @org.login,
        org_id: @org.id,
        fork_source: @repo.nwo,
        fork_source_id: @repo.id,
        user: @user.login,
        user_id: @user.id,
        actor: @org.login,
        actor_id: @org.id,
      }

      assert event = events.pop, "No event was created."
      assert_equal "repo.remove_member", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "user_teams_with_access" do
    test "lists all teams giving the user access to the repo" do
      @team.add_repository(@repo, :pull)

      write_team = create(:team, organization: @org, name: "write-team")
      write_team.add_member(@user)
      write_team.add_repository(@repo, :push)

      team_without_user = create(:team, organization: @org, name: "team-without-user")
      team_without_user.add_repository(@repo, :admin)

      team_without_repo = create(:team, organization: @org, name: "team-without-repo")
      team_without_repo.add_member(@user)

      permissions = Organization::RepositoryPermissions.new(@repo, @user)

      assert_same_elements [@team, write_team], permissions.user_teams_with_access
    end

    test "returns all teams with same permission" do
      repo = create(:public_repository, :minimal, owner: @org)
      team = create(:team, organization: @org, name: "first-team")
      team.add_member(@user)
      team.add_repository(repo, :push)

      team2 = create(:team, organization: @org, name: "second-team")
      team2.add_member(@user)
      team2.add_repository(repo, :push)

      permissions = Organization::RepositoryPermissions.new(repo, @user)

      assert_same_elements [team, team2], permissions.user_teams_with_access
    end

    test "includes teams granting inherited access to a repo" do
      user = create(:user, plan: "small")

      parent_team = create(:team, organization: @org, privacy: :closed)
      child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: parent_team.id)
      parent_team.add_repository(@repo, :admin)
      child_team.add_member(user)

      permissions = Organization::RepositoryPermissions.new(@repo, user)
      assert_same_elements [child_team], permissions.user_teams_with_access
    end
  end

  context "teams_only?" do
    test "true when the user only has team permissions on the repo" do
      @team.add_repository(@repo, :pull)

      write_team = create(:team, organization: @org, name: "write-team")
      write_team.add_member(@user)
      write_team.add_repository(@repo, :push)

      permissions = Organization::RepositoryPermissions.new(@repo, @user)

      assert permissions.teams_only?
    end

    test "false when the user has team and direct permissions on the repo" do
      @team.add_repository(@repo, :pull)
      @repo.add_member(@user)

      permissions = Organization::RepositoryPermissions.new(@repo, @user)

      refute permissions.teams_only?
    end
  end

  context "casualty_ids_from_revoking_all" do
    test "returns the ids of other repos that the user will lose access to if all their permissions on a repo are revoked" do
      @team.add_repository(@repo, :pull)

      expected_casualty_ids = Array.new(2) do |i|
        repo = create(:private_repository, :minimal, owner: @org, name: "casualty-#{i}")
        @team.add_repository(repo, :pull)

        repo.id
      end

      permissions = Organization::RepositoryPermissions.new(@repo, @user)

      assert_same_elements expected_casualty_ids, permissions.casualty_ids_from_revoking_all
    end

    test "includes the ids of repos that the user has access to from multiple teams that will all be revoked" do
      @team.add_repository(@repo, :pull)

      multi_team_repo = create(:private_repository, :minimal, owner: @org, name: "multi-team-repo")
      @team.add_repository(multi_team_repo, :pull)

      extra_team = create(:team, organization: @org, name: "extra-team")
      extra_team.add_member(@user)
      extra_team.add_repository(@repo, :pull)
      extra_team.add_repository(multi_team_repo, :pull)

      permissions = Organization::RepositoryPermissions.new(@repo, @user)

      assert_equal [multi_team_repo.id], permissions.casualty_ids_from_revoking_all
    end

    test "does not include the ids of repos that the user has a direct permission on" do
      @team.add_repository(@repo, :pull)

      collaborating_repo = create(:private_repository, :minimal, owner: @org, name: "collaborating-repo")
      collaborating_repo.add_member(@user, action: :read)
      @team.add_repository(@repo, :pull)

      permissions = Organization::RepositoryPermissions.new(@repo, @user)

      assert_empty permissions.casualty_ids_from_revoking_all
    end

    test "does not include the ids of repos that the user has extra access to through an unrelated team" do
      @team.add_repository(@repo, :pull)

      extra_team_repo = create(:private_repository, :minimal, owner: @org, name: "extra-team-repo")
      @team.add_repository(extra_team_repo, :pull)

      extra_team = create(:team, organization: @org, name: "extra-team")
      extra_team.add_member(@user)
      extra_team.add_repository(extra_team_repo, :pull)

      permissions = Organization::RepositoryPermissions.new(@repo, @user)

      assert_empty permissions.casualty_ids_from_revoking_all
    end

    test "does not include the ids of repos that the user has access to via org admin" do
      # org admin should retain access to all org owned repos
      permissions = Organization::RepositoryPermissions.new(@repo, @org_admin)
      assert_empty permissions.casualty_ids_from_revoking_all

      # even repos they have been granted access via a team they're directly on
      another_repo = create(:private_repository, :minimal, owner: @org)
      another_team = create(:team, organization: @org)
      another_team.add_repository(another_repo, :pull)
      # give org admin direct access to team
      another_team.add_member(@org_admin)

      permissions = Organization::RepositoryPermissions.new(another_repo, @org_admin)
      assert_empty permissions.casualty_ids_from_revoking_all
    end
  end

  context "casualty_ids_from_revoking_active" do
    test "returns only ids of repos that the user will lose access to if their active permission on a repo is revoked" do
      @team.add_repository(@repo, :admin)

      write_team = create(:team, organization: @org, name: "write-team")
      write_team.add_member(@user)
      write_team.add_repository(@repo, :push)

      expected_casualty_ids = Array.new(2) do |i|
        repo = create(:private_repository, :minimal, owner: @org, name: "casualty-#{i}")
        @team.add_repository(repo, :pull)

        repo.id
      end

      # This repo should not be a casualty, since it's on a team that gives the
      # user an inactive permission on the revoked repo.
      2.times do |i|
        repo = create(:private_repository, :minimal, owner: @org, name: "safe-#{i}")
        write_team.add_repository(repo, :push)
      end

      permissions = Organization::RepositoryPermissions.new(@repo, @user)

      assert_same_elements expected_casualty_ids, permissions.casualty_ids_from_revoking_active
    end

    test "does not include ids of repos that the user has a direct permission on" do
      @team.add_repository(@repo, :admin)

      write_team = create(:team, organization: @org, name: "write-team")
      write_team.add_member(@user)
      write_team.add_repository(@repo, :push)

      expected_casualty = create(:private_repository, :minimal, owner: @org, name: "casualty")
      @team.add_repository(expected_casualty, :admin)

      collaborating_repo = create(:private_repository, :minimal, owner: @org, name: "collaborating-repo")
      @team.add_repository(collaborating_repo, :admin)
      collaborating_repo.add_member(@user)

      permissions = Organization::RepositoryPermissions.new(@repo, @user)

      assert_same_elements [expected_casualty.id], permissions.casualty_ids_from_revoking_active
    end
  end

  context "permission_after_revoking_active" do
    test "returns :write if the user has all three permissions" do
      [:pull, :push, :admin].each do |action|
        team = create(:team, organization: @org, name: "#{action}-team")
        team.add_member(@user)
        team.add_repository(@repo, action)
      end

      permissions = Organization::RepositoryPermissions.new(@repo, @user)

      assert_equal :write, permissions.permission_after_revoking_active
    end

    test "returns :read if the user only has :admin and :read" do
      [:pull, :admin].each do |action|
        team = create(:team, organization: @org, name: "#{action}-team")
        team.add_member(@user)
        team.add_repository(@repo, action)
      end

      permissions = Organization::RepositoryPermissions.new(@repo, @user)

      assert_equal :read, permissions.permission_after_revoking_active
    end

    test "returns nil if the user only has :admin" do
      team = create(:team, organization: @org, name: "admin-team")
      team.add_member(@user)
      team.add_repository(@repo, :admin)

      permissions = Organization::RepositoryPermissions.new(@repo, @user)

      assert_nil permissions.permission_after_revoking_active
    end

    test "returns nil if the inactive abilities are inherited" do
      org = create(:organization)
      org.update_default_repository_permission(:none, actor: @org_admin)

      user = create(:user)
      repo = create(:public_repository, :minimal, owner: org)
      parent_team = create(:team, organization: org, privacy: :closed)
      child_team = create(:team, organization: org, privacy: :closed, parent_team_id: parent_team.id)
      grandchild_team = create(:team, organization: org, privacy: :closed, parent_team_id: child_team.id)
      child_team.add_repository(repo, :push)
      parent_team.add_repository(repo, :admin)
      grandchild_team.add_member(user)

      permissions = Organization::RepositoryPermissions.new(repo, user)

      assert_nil permissions.permission_after_revoking_active
    end

    test "returns highest direct permission when inherited permissions are removed" do
      org = create(:organization)
      org.update_default_repository_permission(:none, actor: @org_admin)

      user = create(:user)
      repo = create(:public_repository, :minimal, owner: org)

      parent_team = create(:team, organization: org, privacy: :closed)
      child_team = create(:team, organization: org, privacy: :closed, parent_team_id: parent_team.id)
      grandchild_team = create(:team, organization: org, privacy: :closed, parent_team_id: child_team.id)
      child_team.add_repository(repo, :push)
      parent_team.add_repository(repo, :admin)
      grandchild_team.add_member(user)

      non_nested_team = create(:team, organization: org, privacy: :closed)
      non_nested_team.add_repository(repo, :push)
      non_nested_team.add_member(user)

      permissions = Organization::RepositoryPermissions.new(repo, user)

      assert_equal :write, permissions.permission_after_revoking_active
    end
  end
end
