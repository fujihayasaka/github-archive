# typed: true
# frozen_string_literal: true

require "test_helper"

class UserHovercardContextsOrganizationTeamsTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @organization = create(:organization)
    @teams = create_list(:team, 3, organization: @organization)
  end

  setup do
    @all = Team.where(id: @teams)
  end

  test "returns the jersey octicon" do
    context = UserHovercard::Contexts::OrganizationTeams.new(user: @user, organization: @organization, all: @all)

    assert_equal "people", context.octicon
  end

  test "returns a list of ranked teams" do
    ranked_teams = @teams.reverse
    Team.stubs(:compute_ranked_ids).returns(ranked_teams.map(&:id))

    context = UserHovercard::Contexts::OrganizationTeams.new(user: @user, organization: @organization, all: @all)

    ranked_team_slugs = ranked_teams.map { |team| "@#{team.combined_slug}" }
    assert_equal "Member of #{ranked_team_slugs.to_sentence}", context.message
  end
end
