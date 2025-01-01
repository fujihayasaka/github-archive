# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryPermissionsExportDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:business_plus_organization)
    @org_admin = @org.admins.first
    @repo = create(:repository, owner: @org)
    @team = create(:team, privacy: :closed, organization: @org)
    @maintain_custom_role = create(:custom_repository_role, base_role_id: Role.maintain_role.id, owner_id: @org.id, name: "some-custom-maintain-role")
    @write_custom_role = create(:custom_repository_role, base_role_id: Role.write_role.id, owner_id: @org.id, name: "some-custom-write-role")

    # team_1 assigned: read
    #  '-> team_2 assigned: custom_maintain
    #       '-> team_3 assigned: none
    #       '-> team_4 assigned: triage
    #            '-> team_5 assigned: admin
    @team_1 = create(:team, privacy: :closed, organization: @org, name: "team_1")
    @team_1.add_repository(@repo, :read)

    @team_2 = create(:team, privacy: :closed, organization: @org, parent_team_id: @team_1.id, name: "team_2")
    @team_2.add_repository(@repo, @maintain_custom_role.name)

    @team_3 = create(:team, privacy: :closed, organization: @org, parent_team_id: @team_2.id, name: "team_3")
    @team_4 = create(:team, privacy: :closed, organization: @org, parent_team_id: @team_2.id, name: "team_4")
    @team_4.add_repository(@repo, Role.triage_role.name)

    @team_5 = create(:team, privacy: :closed, organization: @org, parent_team_id: @team_4.id, name: "team_5")
    @team_5.add_repository(@repo, :admin)
  end

  test "shows org admin permissions" do
    expected_result = [
      {
        "source" => @org,
        "permission" => "admin",
      },
      {
        "source" => @repo,
        "permission" => "admin",
        "roleName" => "admin",
      },
    ].sort_by! { |g| g["source"].global_relay_id }
    result = @repo.permission_sources(@org_admin, @org_admin).sort_by { |g| g["source"].global_relay_id }
    assert_equal expected_result, result
  end

  test "shows team member permissions" do
    @team.add_repository(@repo, :push)
    team_member = create(:user)
    @team.add_member(team_member)

    expected_result = [
      {
        "source" => @team,
        "permission" => "write",
        "roleName" => "write"
      },
      {
        "source" => @org,
        "permission" => "read",
      },
    ].sort_by! { |g| g["source"].global_relay_id }

    result = @repo.permission_sources(team_member, @org_admin).sort_by { |g| g["source"].global_relay_id }
    assert_equal expected_result, result
  end

  test "shows org member permissions" do
    org_member = create(:user)
    @org.add_member(org_member, action: "write")

    expected_result = [
      {
        "source" => @org,
        "permission" => "write",
      },
    ]
    result = @repo.permission_sources(org_member, @org_admin)
    assert_equal expected_result, result
  end

  test "shows outside collaborator permissions" do
    repo_collaborator = create(:user)
    @repo.add_member(repo_collaborator)

    expected_result = [
      {
        "source" => @repo,
        "permission" => "write",
        "roleName" => "write"
      },
    ]

    result = @repo.permission_sources(repo_collaborator, @org_admin)
    assert_equal expected_result, result
  end

  test "shows repo member permissions with team membership with lower priority than repo membership" do
    @org.update_default_repository_permission(:none, actor: @org_admin)

    repo_collaborator = create(:user)
    @repo.add_member(repo_collaborator)
    @team.add_repository(@repo, :pull)
    @team.add_member(repo_collaborator)

    expected_result = [
      {
        "source" => @team,
        "permission" => "read",
        "roleName" => "read",
      },
      {
        "source" => @org,
        "permission" => "read",
      },
      {
        "source" => @repo,
        "permission" => "write",
        "roleName" => "write",
      },
    ].sort_by! { |g| g["source"].global_relay_id }


    result = @repo.permission_sources(repo_collaborator, @org_admin).sort_by { |g| g["source"].global_relay_id }
    assert_equal expected_result, result
  end

  test "shows repo member permissions with team membership with higher priority than repo membership" do
    @org.update_default_repository_permission(:none, actor: @org_admin)

    repo_collaborator = create(:user)
    @repo.add_member(repo_collaborator, action: :read)
    @team.add_repository(@repo, :push)
    @team.add_member(repo_collaborator)

    expected_result = [
      {
        "source" => @team,
        "permission" => "write",
        "roleName" => "write",
      },
      {
        "source" => @org,
        "permission" => "read",
      },
      {
        "source" => @repo,
        "permission" => "read",
        "roleName" => "read",
      },
    ].sort_by! { |g| g["source"].global_relay_id }

    result = @repo.permission_sources(repo_collaborator, @org_admin).sort_by { |g| g["source"].global_relay_id }
    assert_equal expected_result, result
  end

  test "shows child team member permissions" do
    @org.update_default_repository_permission(:none, actor: @org_admin)

    @team.add_repository(@repo, :push)
    child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: @team.id)
    team_member = create(:user)
    child_team.add_member(team_member)

    expected_result = [
      {
        "source" => child_team,
        "permission" => "write",
        "roleName" => "write",
      },
      {
        "source" => @org,
        "permission" => "read",
      },
    ].sort_by! { |g| g["source"].global_relay_id }

    result = @repo.permission_sources(team_member, @org_admin).sort_by { |g| g["source"].global_relay_id }
    assert_equal expected_result, result
  end

  test "shows org admin permissions when repo is a fork" do
    foreign_repo = create(:repository, owner: create(:user))
    forked_repo, reason = foreign_repo.fork(org: @org, forker: @org_admin)

    expected_result = [
      {
        "source" => @org,
        "permission" => "admin",
      },
      {
        "source" => forked_repo,
        "permission" => "admin",
        "roleName" => "admin",
      },
    ].sort_by! { |g| g["source"].global_relay_id }

    result = forked_repo.permission_sources(@org_admin, @org_admin).sort_by { |g| g["source"].global_relay_id }
    assert_equal expected_result, result
  end

  test "shows repo member permissions when repo is a fork" do
    foreign_repo = create(:repository, owner: create(:user))
    forked_repo, reason = foreign_repo.fork(org: @org, forker: @org_admin)

    repo_collaborator = create(:user)
    forked_repo.add_member(repo_collaborator)

    expected_result = [
      {
        "source" => forked_repo,
        "permission" => "write",
        "roleName" => "write",
      },
    ]

    result = forked_repo.permission_sources(repo_collaborator, @org_admin)
    assert_equal expected_result, result
  end

  test "shows role name for triage role" do
    member = create(:user)
    @org.add_member(member)
    @repo.add_member(member, action: :triage)
    result = @repo.permission_sources(member, @org_admin).find { |r| r["source"] == @repo }
    assert_equal "read", result["permission"]
    assert_equal Role.triage_role.name, result["roleName"]
  end

  test "shows role name for custom write role" do
    member = create(:user)
    @org.add_member(member)
    @repo.add_member(member, action: @write_custom_role.name)
    result = @repo.permission_sources(member, @org_admin).find { |r| r["source"] == @repo }
    assert_equal "write", result["permission"]
    assert_equal @write_custom_role.name, result["roleName"]
  end

  test "shows role name for custom maintain role" do
    member = create(:user)
    @org.add_member(member)
    @repo.add_member(member, action: @maintain_custom_role.name)
    result = @repo.permission_sources(member, @org_admin).find { |r| r["source"] == @repo }
    assert_equal "write", result["permission"]
    assert_equal @maintain_custom_role.name, result["roleName"]
  end

  test "shows role name for team custom maintain role" do
    member = create(:user)
    @org.add_member(member)

    @team.add_member(member)
    @team.add_repository(@repo, @maintain_custom_role.name)

    result = @repo.permission_sources(member, @org_admin).find { |r| r["source"] == @team }
    assert_equal "write", result["permission"]
    assert_equal @maintain_custom_role.name, result["roleName"]
  end

  test "shows role name for teams in multilevel heirarchy" do
    member = create(:user)
    @org.add_member(member)

    @team_5.add_member(member)
    result = @repo.permission_sources(member, @org_admin)

    expected_results = [
      { "permission" => "read", "roleName" => "read" },
      { "permission" => "read", "roleName" => "triage" },
      { "permission" => "write", "roleName" => @maintain_custom_role.name },
      { "permission" => "admin", "roleName" => "admin" },
    ]

    team_5_results = result.select { |r| r["source"] == @team_5 }.map { |ps| ps.slice("permission", "roleName") }
    assert_same_elements expected_results, team_5_results
  end

  test "shows team permissions from ancestor teams even when assigned team has no access" do
    member = create(:user)
    @org.add_member(member)
    @team_3.add_member(member)

    result = @repo.permission_sources(member, @org_admin)

    expected_results = [
      { "permission" => "read", "roleName" => "read" },
      { "permission" => "write", "roleName" => @maintain_custom_role.name }
    ]

    team_3_results = result.select { |r| r["source"] == @team_3 }.map { |ps| ps.slice("permission", "roleName") }
    assert_same_elements expected_results, team_3_results
  end

  test "async method batches queries" do
    repo2 = create(:repository, owner: @org)

    users = 3.times.map { create(:user) }
    users.each do |user|
      @repo.add_member(user, action: :write)
      repo2.add_member(user, action: :maintain)
    end

    async_results, async_queries = log_cleaned_queries do
      promises = []
      users.each do |user|
        promises << @repo.async_permission_sources(user, @org_admin)
        promises << repo2.async_permission_sources(user, @org_admin)
      end
      Promise.all(promises).sync
    end

    sync_results, sync_queries = log_cleaned_queries do
      results = []
      users.each do |user|
        results << @repo.permission_sources(user, @org_admin)
        results << repo2.permission_sources(user, @org_admin)
      end
      results
    end

    assert async_queries.length < sync_queries.length
    assert_equal sync_results, async_results
  end
end
