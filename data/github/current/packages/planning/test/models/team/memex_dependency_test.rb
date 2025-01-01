# typed: true
# frozen_string_literal: true

require "test_helper"

class Team::MemexDependencyTest < GitHub::TestCase
  fixtures do
    @admin = create(:verified_user)
    @org = create(:organization, admin: @admin)
    @team = create(:team, organization: @org)
    @org_member = create(:verified_user)
    @org.add_member(@org_member)
  end

  context "#can_be_added_to_memex_project?" do
    test "returns false when no project owner is given" do
      refute @team.can_be_added_to_memex_project?(memex_owner: nil, viewer: @admin)
    end

    test "returns false when the project owner is not an organization" do
      refute @team.can_be_added_to_memex_project?(memex_owner: @admin, viewer: @admin)
    end

    test "returns false when the project owner is not the team's organization" do
      other_org = create(:organization)
      refute @team.can_be_added_to_memex_project?(memex_owner: other_org, viewer: @admin)
    end

    test "returns false when the viewer lacks read access on the team" do
      secret_team = create(:secret_team, organization: @org)
      refute secret_team.can_be_added_to_memex_project?(memex_owner: @org, viewer: @org_member)
    end

    test "returns true when the project owner is the team's org and the viewer can see the team" do
      assert @team.can_be_added_to_memex_project?(memex_owner: @org, viewer: @admin)

      @team.add_member(@org_member)
      assert @team.can_be_added_to_memex_project?(memex_owner: @org, viewer: @org_member)
    end

    test "can be efficiently loaded for many teams at once for an organization Memex owner" do
      viewer = @org_member
      memex_owner = @org
      team1 = @team
      team2 = create(:team, organization: memex_owner)
      team3, team4 = create_pair(:secret_team, organization: memex_owner)
      teams = [team1, team2, team3, team4]

      team2.add_member(viewer)
      team4.add_member(viewer)

      assert_query_count(1, ignore_feature_flags: true) do
        GitHub::PrefillAssociations.prefill_batch_method(teams, :can_be_added_to_memex_project?, {
          memex_owner: memex_owner,
          viewer: viewer,
        })
      end

      assert_query_count(0) do
        refute team1.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: viewer),
          "should not be able to see team viewer does not belong to"
        assert team2.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: viewer),
          "should be able to see team viewer belongs to"
        refute team3.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: viewer),
          "should not be able to see secret team viewer does not belong to"
        assert team4.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: viewer),
          "should be able to see secret team viewer belongs to"
      end
    end

    test "can be efficiently loaded for many teams at once for a user Memex owner" do
      viewer = @org_member
      memex_owner = viewer
      team1 = @team
      team2 = create(:team, organization: @org)
      team3, team4 = create_pair(:secret_team, organization: @org)
      teams = [team1, team2, team3, team4]

      team2.add_member(viewer)
      team4.add_member(viewer)

      assert_query_count(0) do
        GitHub::PrefillAssociations.prefill_batch_method(teams, :can_be_added_to_memex_project?, {
          memex_owner: memex_owner,
          viewer: viewer,
        })
      end

      assert_query_count(0) do
        refute team1.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: viewer)
        refute team2.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: viewer)
        refute team3.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: viewer)
        refute team4.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: viewer)
      end
    end
  end
end
