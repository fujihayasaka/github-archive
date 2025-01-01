# typed: true
# frozen_string_literal: true

require "test_helper"

class ReviewRequestDelegationExcludedMemberTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @team_member = create(:user)
    @team_member2 = create(:user)
    @team = create(:team, organization: @org)
    @team.add_member @team_member
    @team.add_member @team_member2
  end

  context "#update_excluded_team_members" do
    test "updates the list of team members to never assign to code review" do
      @team.update!(
        review_request_delegation_enabled: true,
        review_request_delegation_member_count: 2
      )
      ReviewRequestDelegationExcludedMember.update_excluded_team_members(
        team: @team,
        excluded_member_ids: [@team_member.id, @team_member2.id],
        exclude_team_members: true
      )

      assert_equal @team.review_request_delegation_excluded_members.count, 2
    end

    test "destroys list of excluded team members if exclude_team_members is false" do
      @team.update!(
        review_request_delegation_enabled: true,
        review_request_delegation_member_count: 2
      )
      ReviewRequestDelegationExcludedMember.update_excluded_team_members(
        team: @team,
        excluded_member_ids: [@team_member.id, @team_member2.id],
        exclude_team_members: false
      )

      assert_equal @team.review_request_delegation_excluded_members.count, 0
    end

    test "clears list if exclude_team_members is empty" do
      @team.update!(
        review_request_delegation_enabled: true,
        review_request_delegation_member_count: 2
      )
      ReviewRequestDelegationExcludedMember.update_excluded_team_members(
        team: @team,
        excluded_member_ids: [],
        exclude_team_members: true
      )

      assert_equal @team.review_request_delegation_excluded_members.count, 0
    end
  end
end
