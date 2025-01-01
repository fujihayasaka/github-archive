# typed: true
# frozen_string_literal: true

require "test_helper"

module RepositoryMemberRolesHelper
  def repo_roles(repository: @org_repo, current_user: @owner, members: @members, teams: [])
    ::RepositoryMemberRoles.fetch(
      repository: repository,
      current_user: current_user,
      members: members,
      teams: teams,
    )
  end
end

class RepositoryMemberRolesTest < GitHub::TestCase
  include RepositoryMemberRolesHelper

  fixtures do
    @org = create(:business_plus_organization)
    @org_repo = create(:repository, :minimal, owner: @org)
    @owner = @org.admins.first

    @triage_member, @maintain_member, @collaborator = create(:user), create(:user), create(:user)
    @members = [@triage_member, @maintain_member, @collaborator, @owner]
    @org.add_member(@triage_member)
    @org.add_member(@maintain_member)
    @org_repo.add_member(@triage_member, action: :triage)
    @org_repo.add_member(@maintain_member, action: :maintain)
    @org_repo.add_member(@collaborator, action: :read)
    @org_repo.add_member(@owner, action: :admin)

    @write_team = create(:team, organization: @org, privacy: :closed)
    @write_team.add_repository(@org_repo, :push)
    @write_team.add_member(@triage_member)
    @write_team.add_member(@maintain_member)
    @write_team.add_member(@triage_member)
    @custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id, owner_type: "Organization", base_role_id: Role.write_role.id)
  end

  context "mixed roles" do
    test "returns mixed role for member of nested team" do
      user = create(:user)
      @org.add_member(user)
      @org_repo.add_member(user, action: :triage)

      child_team = create(:team, organization: @org, parent_team_id: @write_team.id, privacy: :closed)
      child_team.add_repository(@org_repo, :pull)
      child_team.add_member(user)

      assert @org_repo.writable_by?(@write_team)
      assert @org_repo.readable_by?(child_team)

      assert UserRole.find_by(actor: user, target: @org_repo, role: Role.triage_role)

      assert_equal :write, repo_roles(members: [user]).mixed_role_for(user)[:team_role]
      assert_equal [@write_team], repo_roles(members: [user]).teams_giving_mixed_role(user)
    end

    test "returns highest team role when team gives role higher than user's direct role" do
      assert @org_repo.writable_by?(@write_team)
      assert UserRole.find_by(actor: @triage_member, target: @org_repo, role: Role.triage_role)

      assert_equal :write, repo_roles.mixed_role_for(@triage_member)[:team_role]
      assert_nil repo_roles.mixed_role_for(@triage_member)[:default_role]
      assert_equal [@write_team], repo_roles.teams_giving_mixed_role(@triage_member)
    end

    test "no mixed role when team and org doesn't give role higher than user's direct role" do
      assert @org_repo.writable_by?(@write_team)
      assert UserRole.find_by(actor: @maintain_member, target: @org_repo, role: Role.maintain_role)

      assert_nil repo_roles.mixed_role_for(@maintain_member)
      assert_equal [], repo_roles.teams_giving_mixed_role(@maintain_member)
    end

    test "no mixed role when team w/custom role's base role is below user's direct role" do
      read_custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id, owner_type: "Organization", base_role_id: Role.read_role.id)
      @write_team.update_repository_permission(@org_repo, read_custom_role.name)

      assert_nil repo_roles.mixed_role_for(@triage_member)
      assert_equal [], repo_roles.teams_giving_mixed_role(@triage_member)
    end

    test "works with custom roles" do
      @write_team.update_repository_permission(@org_repo, @custom_role.name)
      assert UserRole.find_by(actor: @triage_member, target: @org_repo, role: Role.triage_role)
      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:write, actor: @org.owner)
      end
      assert_equal :write, repo_roles.mixed_role_for(@triage_member)[:team_role]
      assert_equal :write, repo_roles.mixed_role_for(@triage_member)[:default_role]
      assert_equal [@write_team], repo_roles.teams_giving_mixed_role(@triage_member)
      assert_equal @org, repo_roles.org_giving_mixed_role(@triage_member)
    end

    test "works if a user has a direct custom role" do
      assert @org_repo.writable_by?(@write_team)
      @org_repo.update_member(@triage_member, action: @custom_role.name)
      assert UserRole.find_by(actor: @triage_member, target: @org_repo, role: @custom_role)

      assert_nil repo_roles.mixed_role_for(@triage_member)
      assert_equal [], repo_roles.teams_giving_mixed_role(@triage_member)
    end

    test "no mixed role for outside collaborator" do
      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:write, actor: @org.owner)
      end

      assert @org_repo.readable_by?(@collaborator)

      assert_nil repo_roles.mixed_role_for(@collaborator)
      assert_equal [], repo_roles.teams_giving_mixed_role(@collaborator)
    end

    test "no mixed roles when there are no input members" do
      assert_equal [], repo_roles(members: []).teams_giving_mixed_role(@maintain_member)
    end

    test "mixed role returns default and team role if default role is below admin" do
      assert @org_repo.writable_by?(@write_team)
      assert UserRole.find_by(actor: @triage_member, target: @org_repo, role: Role.triage_role)

      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:write, actor: @org.owner)
      end

      assert_equal :write, repo_roles.mixed_role_for(@triage_member)[:default_role]
      assert_equal @org, repo_roles.org_giving_mixed_role(@triage_member)

      assert_equal :write, repo_roles.mixed_role_for(@triage_member)[:team_role]
      assert_equal [@write_team], repo_roles.teams_giving_mixed_role(@triage_member)
    end

    test "mixed role returns only default role if default role is admin" do
      assert @org_repo.writable_by?(@write_team)
      assert UserRole.find_by(actor: @triage_member, target: @org_repo, role: Role.triage_role)

      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:admin, actor: @org.owner)
      end

      assert_equal :admin, repo_roles.mixed_role_for(@triage_member)[:default_role]
      assert_equal @org, repo_roles.org_giving_mixed_role(@triage_member)

      assert_nil repo_roles.mixed_role_for(@triage_member)[:team_role]
      assert_nil repo_roles.mixed_role_for(@triage_member)[:org_role]
    end

    test "mixed role returns org admin if the user is org admin" do
      assert @org_repo.writable_by?(@write_team)
      assert UserRole.find_by(actor: @triage_member, target: @org_repo, role: Role.triage_role)

      @org.update_member(@triage_member, action: :admin)
      @triage_member.reload

      assert repo_roles.mixed_role_for(@triage_member)[:org_admin]
      assert_equal @org, repo_roles.org_giving_mixed_role(@triage_member)

      assert_nil repo_roles.mixed_role_for(@triage_member)[:team_role]
      assert_nil repo_roles.mixed_role_for(@triage_member)[:default_role]

      # we also bail out of computation when the default role is admin
      # as the org admin is the highest role
      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:admin, actor: @org.owner)
      end

      @org_repo.reload

      assert repo_roles.mixed_role_for(@triage_member)[:org_admin]
      assert_equal @org, repo_roles.org_giving_mixed_role(@triage_member)

      assert_nil repo_roles.mixed_role_for(@triage_member)[:team_role]
      assert_nil repo_roles.mixed_role_for(@triage_member)[:default_role]
    end

    test "mixed role when org does give role higher than user's direct role but team doesn't" do
      assert @org_repo.writable_by?(@write_team)
      assert UserRole.find_by(actor: @maintain_member, target: @org_repo, role: Role.maintain_role)
      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:admin, actor: @org.owner)
      end

      assert_equal :admin, repo_roles.mixed_role_for(@maintain_member)[:default_role]
      assert_equal @org, repo_roles.org_giving_mixed_role(@maintain_member)
      assert_nil repo_roles.mixed_role_for(@maintain_member)[:team_role]
      assert_equal [], repo_roles.teams_giving_mixed_role(@maintain_member)
    end

    test "no mixed role if the repo is user owned" do
      repo = create(:repository, :minimal, owner: @owner)
      repo.add_member(@collaborator, action: :read)

      assert_nil repo_roles(members: [@collaborator], repository: repo).mixed_role_for(@collaborator)
      assert_nil repo_roles(members: [@collaborator], repository: repo).org_giving_mixed_role(@collaborator)
      assert_equal [], repo_roles(members: [@collaborator], repository: repo).teams_giving_mixed_role(@collaborator)
    end


    context "teams" do
      test "displays mixed role for a child team" do
        child_team = create(:team, organization: @org, parent_team_id: @write_team.id, privacy: :closed)
        child_team.add_repository(@org_repo, :pull)
        assert @org_repo.readable_by?(child_team)

        assert_equal :write, repo_roles(teams: [child_team]).mixed_role_for(child_team)[:team_role]
      end

      test "returns mixed role for double nested team" do
        child_team = create(:team, organization: @org, parent_team_id: @write_team.id, privacy: :closed)
        child_team.add_repository(@org_repo, :pull)

        grandchild_team = create(:team, organization: @org, parent_team_id: child_team.id, privacy: :closed)
        grandchild_team.add_repository(@org_repo, :pull)

        assert @org_repo.writable_by?(@write_team)
        assert @org_repo.readable_by?(child_team)
        assert @org_repo.readable_by?(grandchild_team)

        assert_equal :write, repo_roles(teams: [child_team]).mixed_role_for(child_team)[:team_role]
      end

      test "displays mixed for a child team for a parent with a custom role" do
        child_team = create(:team, organization: @org, parent_team_id: @write_team.id, privacy: :closed)
        @write_team.update_repository_permission(@org_repo, @custom_role.name)
        child_team.add_repository(@org_repo, :pull)
        assert @org_repo.readable_by?(child_team)

        assert_equal :write, repo_roles(teams: [child_team]).mixed_role_for(child_team)[:team_role]
      end

      test "works if the child team has a custom role" do
        child_team = create(:team, organization: @org, parent_team_id: @write_team.id, privacy: :closed)
        child_team.add_repository(@org_repo, @custom_role.name)
        assert @org_repo.readable_by?(child_team)

        assert_nil repo_roles(teams: [child_team]).mixed_role_for(child_team)
      end

      test "displays mixed roles when there are multiple parent teams" do
        child_team = create(:team, organization: @org, parent_team_id: @write_team.id, privacy: :closed)
        child_team.add_repository(@org_repo, :triage)

        grandchild_team = create(:team, organization: @org, parent_team_id: child_team.id, privacy: :closed)
        grandchild_team.add_repository(@org_repo, :pull)

        assert_equal :write, repo_roles(teams: [grandchild_team, child_team]).mixed_role_for(grandchild_team)[:team_role]
      end
    end
  end

  context "direct roles" do
    test "returns direct role for a team" do
      assert_equal :write, repo_roles.direct_role_for(@write_team)
    end

    test "returns direct role for users" do
      assert_equal :read, repo_roles.direct_role_for(@collaborator)
      assert_equal :triage, repo_roles.direct_role_for(@triage_member)
      assert_equal :maintain, repo_roles.direct_role_for(@maintain_member)
      assert_equal :admin, repo_roles.direct_role_for(@owner)
    end

    test "returns nil for actor without access to the repo" do
      assert_nil repo_roles.direct_role_for(create(:user))
      assert_nil repo_roles.direct_role_for(create(:team, organization: @org))
    end

    test "returns nil for input which is not User nor Team" do
      assert_nil repo_roles.direct_role_for(@org_repo)
    end
  end
end
