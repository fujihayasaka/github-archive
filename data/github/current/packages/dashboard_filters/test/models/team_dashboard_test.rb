# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamDashboardTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @org = create(:organization, admin: @owner)
    @team = create(:team, name: "myTeam", organization: @org)
  end

  context "validations" do
    test "requires a team" do
      dashboard = build(:team_dashboard, team: nil)
      refute_predicate dashboard, :valid?
      assert_includes dashboard.errors[:team], "can't be blank"
    end
  end

  test "has many shortcuts" do
    dashboard = create(:team_dashboard, team: @team)
    shortcut = create(:team_search_shortcut, dashboard: dashboard)
    assert_equal [shortcut], dashboard.shortcuts
  end

  test "is destroyed when a team is destroyed" do
    team = create(:team, name: "deleteMe", organization: @org)
    dashboard = create(:team_dashboard, team: team)
    assert_changes -> { ::TeamDashboard.count }, from: 1, to: 0 do
      perform_enqueued_jobs(only: [DestroyTeamDependantsJob]) do
        team.destroy
      end
    end
  end

  test "destroys dependent shortcuts" do
    dashboard = create(:team_dashboard, team: @team)
    create(:team_search_shortcut, dashboard: dashboard)

    assert_changes -> { ::TeamSearchShortcut.count }, from: 1, to: 0 do
      dashboard.destroy
    end
  end

  test "traces prioritize_dependent! execution" do
    dashboard = create(:team_dashboard, team: @team)
    shortcut = create(:team_search_shortcut, dashboard: dashboard)

    exporter.reset
    assert dashboard.prioritize_dependent!(shortcut, position: :top)

    span = find_span_by(name: "team_dashboard#prioritize_dependent!")

    refute_nil span
    assert_equal dashboard.id, span.attributes["context_id"]
    assert_equal dashboard.class.name, span.attributes["context_type"]
  end
end
