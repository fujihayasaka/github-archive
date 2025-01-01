# typed: true
# frozen_string_literal: true

require "test_helper"

class SuggesterTeamSuggesterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @viewer = create(:user)
    @team = create :team
    @team.add_member(@viewer)
    @authorizing_filter = cap_authorizing_filter.freeze
  end

  test "includes members of the organization" do
    member = create(:user)
    @team.add_member(member)

    suggester = create_suggester_with_cap_stubbing(viewer: @viewer, team: @team)

    assert suggester.mentions.any? { |x| x[:login] == member.login }
  end

  test "excludes members of the organization that have the viewer blocked" do
    member = create(:user)
    @team.add_member(member)
    member.block @viewer

    suggester = create_suggester_with_cap_stubbing(viewer: @viewer, team: @team)

    refute suggester.mentions.any? { |x| x[:login] == member.login }
  end

  test "includes teams of the organization" do
    suggester = create_suggester_with_cap_stubbing(viewer: @viewer, team: @team)

    assert suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == @team.id }
  end

  test "excludes users who are not members of the organization" do
    user = create(:user)
    suggester = create_suggester_with_cap_stubbing(viewer: @viewer, team: @team)

    refute suggester.mentions.any? { |x| x[:login] == user.login }
  end

  test "excludes teams that are not part of the organization" do
    other_team = create :team
    suggester = create_suggester_with_cap_stubbing(viewer: @viewer, team: @team)

    refute suggester.mentions.any? { |x| x[:type] == "team" && x[:id] == other_team.id }
  end

  def create_suggester_with_cap_stubbing(viewer:, team:)
    Suggester::TeamSuggester.new(viewer: viewer, team: team, cap_filter: @authorizing_filter)
  end
end
