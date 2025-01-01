# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsTeamTest < GitHub::TestCase
  fixtures do
    @team = create :team, privacy: :closed, slug: "zzzz", name: "ZZZZ"
    @org = @team.organization

    4.times { @team.add_member create(:user) }
  end

  context ".for_organization" do
    test "returns empty result set if org has no teams" do
      org = create(:organization)
      teams = Stafftools::Team.for_organization(org)
      assert_equal 0, teams.size
    end

    test "finds the org's teams" do
      teams = Stafftools::Team.for_organization(@org)
      assert_equal 1, teams.size
    end

    test "counts the team members" do
      teams = Stafftools::Team.for_organization(@org)
      assert_equal 4, teams.first.num_members
    end

    test "total team member count includes users in descendant teams" do
      child_team  = create :team, organization: @org, privacy: :closed, parent_team_id: @team.id
      2.times { child_team.add_member create(:user) }

      teams = Stafftools::Team.for_organization(@org)
      assert_equal 6, teams[teams.index(@team)].num_members
    end

    test "finds matching teams given query" do
      team = create :team, organization: @org, privacy: :closed, slug: "aaaa", name: "AAAA"
      teams = Stafftools::Team.for_organization(@org, query: "aaa", page: 1)
      assert_equal 1, teams.size
      assert_equal team.slug, teams.first.slug
    end

    test "total team member count only includes unique users" do
      child_team  = create :team, organization: @org, privacy: :closed, parent_team_id: @team.id
      child_team.add_member @team.members[0]
      child_team.add_member @team.members[1]
      child_team.add_member create(:user)

      teams = Stafftools::Team.for_organization(@org)
      assert_equal 5, teams[teams.index(@team)].num_members
    end
  end

  context "#externally_managed?" do
    test "returns true if the team is externally_managed" do
      team = Stafftools::Team.new(@team, 1, externally_managed: true)
      assert_predicate team, :externally_managed?
    end

    test "returns false if the team is not externally_managed" do
      team = Stafftools::Team.new(@team, 1, externally_managed: false)
      refute_predicate team, :externally_managed?
    end

    test "returns false if the team externally_managed is not passed in" do
      team = Stafftools::Team.new(@team, 1)
      refute_predicate team, :externally_managed?
    end
  end

  context "#pending_team_membership_requests" do
    test "returns collection if the team has requests" do
      membership_request = Struct.new(:status).new(:good_to_go) # we don't actually care what this is in this test
      team = Stafftools::Team.new(@team, 1, pending_team_membership_requests: [membership_request])
      assert_same_elements [membership_request], team.pending_team_membership_requests
    end

    test "returns empty collection if the team has no requests" do
      team = Stafftools::Team.new(@team, 1, pending_team_membership_requests: [])
      assert_empty team.pending_team_membership_requests
    end

    test "returns empty collection if the team gets no requests passed in" do
      team = Stafftools::Team.new(@team, 1)
      assert_empty team.pending_team_membership_requests
    end
  end

  context "#mapping_sync_status" do
    test "returns the status of the first group_mapping passed in" do
      mapping = Struct.new(:status).new("succeeded")
      team = Stafftools::Team.new(@team, 1, group_mappings: [mapping])
      assert_equal "succeeded", team.mapping_sync_status
    end

    test "handles no group_mappings" do
      team = Stafftools::Team.new(@team, 1)
      assert_nil team.mapping_sync_status
    end
  end

  context "#mapping_sync_status_label" do
    test "returns orange if the status is 'failed'" do
      failed_mapping = Struct.new(:status).new("failed")
      team = Stafftools::Team.new(@team, 1, group_mappings: [failed_mapping])
      assert_equal :orange, team.mapping_sync_status_label
    end

    test "returns secondary if the status is other than 'failed'" do
      mapping = Struct.new(:status).new("succeeded")
      team = Stafftools::Team.new(@team, 1, group_mappings: [mapping])
      assert_equal :secondary, team.mapping_sync_status_label
    end
  end
end
