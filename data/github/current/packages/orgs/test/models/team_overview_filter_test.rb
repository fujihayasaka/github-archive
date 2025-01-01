# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamOverviewFilterTest < GitHub::TestCase
  fixtures do
    @org_admin = create(:user, login: "org-admin")
    @org       = create(:organization, admin: @org_admin)
    @team      = create(:team, organization: @org, name: "Cool Team")
    @team2     = create(:team, organization: @org, name: "Other Team")
    @member    = create(:user, login: "member")
    @team.add_member @member
  end

  context "results, when including all visible teams" do
    test "matches on team name" do
      filter = TeamOverviewFilter.new(@org, @org_admin, "Cool Team").include_visible
      assert_equal [@team], filter.results
    end

    test "matches on team slug" do
      filter = TeamOverviewFilter.new(@org, @org_admin, "cool-team").include_visible
      assert_equal [@team], filter.results
    end

    test "is case-insensitive" do
      filter = TeamOverviewFilter.new(@org, @org_admin, "cool team").include_visible
      assert_equal [@team], filter.results
    end

    test "returns nothing when there's no match" do
      filter = TeamOverviewFilter.new(@org, @org_admin, "no match").include_visible
      assert_empty filter.results
    end

    test "returns teams of which a given user is a member" do
      filter = TeamOverviewFilter.new(@org, @member, "@member").include_visible
      assert_equal [@team], filter.results
    end

    test "shows all teams visible to a user" do
      admin_sees_all = TeamOverviewFilter.new(@org, @org_admin, "").include_visible
      assert_same_elements @org.teams, admin_sees_all.results

      member_sees_member_teams = TeamOverviewFilter.new(@org, @member, "").include_visible
      assert_same_elements [@team], member_sees_member_teams.results
    end

    test "filters teams containing specific members" do
      third_team = create(:team, organization: @org)
      third_team.add_member @member
      third_user = create(:user, login: "third")
      third_team.add_member third_user

      one_user = TeamOverviewFilter.new(@org, @org_admin, "@member").include_visible
      assert_same_elements [@team, third_team], one_user.results

      two_users = TeamOverviewFilter.new(@org, @org_admin, "@member @third").include_visible
      assert_equal [third_team], two_users.results
    end
  end

  context "results" do
    test "lists only the teams the user is a member of" do
      filter = TeamOverviewFilter.new(@org, @member, "")
      assert_equal [@team], filter.results
    end

    test "filters teams by name" do
      third_team = create(:team, organization: @org)
      third_team.add_member @member

      all_member_teams = TeamOverviewFilter.new(@org, @member, "")
      assert_same_elements [@team, third_team], all_member_teams.results

      filtered_teams = TeamOverviewFilter.new(@org, @member, "cool-team")
      assert_equal [@team], filtered_teams.results
    end

    test "filters teams by specified members" do
      third_team = create(:team, organization: @org)
      third_team.add_member @member
      third_user = create(:user, login: "third")
      third_team.add_member third_user

      filter = TeamOverviewFilter.new(@org, @member, "@third")
      assert_equal [third_team], filter.results
    end

    test "orders results by team name when the viewer is an owner" do
      org_owner = create(:user, login: "org-owner")
      org       = create(:organization, admin: org_owner)

      team_b = create(:team, organization: org, name: "team-b")
      team_b.add_member(org_owner)

      team_a = create(:team, organization: org, name: "team-a")
      team_a.add_member(org_owner)

      filter = TeamOverviewFilter.new(org, org_owner, "")

      assert_equal [team_a, team_b], filter.results
    end

    test "filters teams by secret visibility" do
      team3 = create(:team, organization: @org, privacy: :closed)
      team3.add_member(@member)

      filter = TeamOverviewFilter.new(@org, @member, "visibility:secret")
      assert_equal [@team], filter.results
    end

    test "filters teams by closed visiblity" do
      team3 = create(:team, organization: @org, privacy: :closed)
      team3.add_member(@member)

      filter = TeamOverviewFilter.new(@org, @member, "visibility:visible")
      assert_equal [team3], filter.results
    end

    test "filters teams by no members" do
      team3 = create(:team, organization: @org, name: "Z Team")

      filter = TeamOverviewFilter.new(@org, @org_admin, "members:empty").include_visible
      assert_equal [@team2, team3], filter.results
    end

    test "filters teams by teams the user is a member of" do
      filter = TeamOverviewFilter.new(@org, @member, "members:me")
      assert_equal [@team], filter.results
    end

    test "orders results by team name when the viewer is a non-owner member" do
      org        = create(:organization)
      org_member = create(:user, login: "org-member")
      org.add_member(org_member)

      team_b = create(:team, organization: org, name: "team-b")
      team_b.add_member(org_member)

      team_a = create(:team, organization: org, name: "team-a")
      team_a.add_member(org_member)

      filter = TeamOverviewFilter.new(org, org_member, "")

      assert_equal [team_a, team_b], filter.results
    end
  end
end
