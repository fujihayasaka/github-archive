# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamMemexesDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user)
    @team = create(:team, organization: @org)
    @memexes = create_list(:memex_project, 2, owner: @org).tap do |memexes|
      memexes.each do |memex|
        memex.grant_role(@team, Role.internal_role_by_name(:project_reader))
      end
    end
  end

  test "memexes the team has access to are being returned" do
    assert_same_elements @memexes, @team.accessible_memexes_scope(@team.memex_projects, @user)
  end

  test "memexes the team doesn't have the access to are excluded from the result" do
    memex = create(:memex_project, owner: @org)
    refute_includes @team.accessible_memexes_scope(@team.memex_projects, @user), memex
  end

  test "if the team is granted access to a memex, it is included in the results" do
    memex = create(:memex_project, owner: @org)
    memex.grant_role(@team, Role.internal_role_by_name(:project_reader))
    assert_includes @team.accessible_memexes_scope(@team.memex_projects, @user), memex
  end

  test "if the team access to a memex is revoked, it is excluded from the results" do
    memex = @memexes.first
    memex.revoke_role(@team, Role.internal_role_by_name(:project_reader))
    refute_includes @team.accessible_memexes_scope(@team.memex_projects, @user), memex
  end

  test "viewer who is not an org member can't see any projects" do
    user = create(:user)
    assert_empty @team.accessible_memexes_scope(@team.memex_projects, user)
  end
end
