# typed: true
# frozen_string_literal: true

require "test_helper"

class UserDashboardTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner")
    @org = create(:organization, admin: @owner)
    @team = create(:team, organization: @org)
  end

  context "validations" do
    test "requires a user" do
      dashboard = build(:user_dashboard, user: nil)
      refute_predicate dashboard, :valid?
      assert_includes dashboard.errors[:user], "can't be blank"
    end
  end

  test "has many shortcuts" do
    dashboard = create(:user_dashboard, user: @owner)
    shortcut = create(:search_shortcut, dashboard: dashboard)
    assert_equal [shortcut], dashboard.shortcuts
  end

  test "is destroyed when a user is destroyed" do
    delete_user = create(:user, login: "deleteMe")
    create(:user_dashboard, user: delete_user)

    assert_changes -> { ::UserDashboard.count }, from: 1, to: 0 do
      delete_user.destroy!
    end
  end

  test "destroys dependent shortcuts" do
    dashboard = create(:user_dashboard, user: @owner)
    create(:search_shortcut, dashboard: dashboard)

    assert_changes -> { ::SearchShortcut.count }, from: 1, to: 0 do
      dashboard.destroy
    end
  end

  test "returns sync and async mobile nav links" do
    dashboard = create(:user_dashboard, user: @owner)
    assert_equal ::Mobile::HomeNavLink.default_links, dashboard.mobile_nav_links
    assert_equal ::Mobile::HomeNavLink.default_links, dashboard.async_mobile_nav_links.sync
  end

  test "updates a user's nav links" do
    dashboard = create(:user_dashboard, user: @owner)
    nav_links = dashboard.mobile_nav_links

    dashboard.update_mobile_nav_links!(
      sorted_links: nav_links.reverse.map(&:identifier),
      hidden_links: []
    )

    assert_equal nav_links.reverse, dashboard.mobile_nav_links
  end

  context "selected teams" do
    test "can select teams" do
      dashboard = create(:user_dashboard, user: @owner)
      dashboard.selected_teams << @team
      assert_equal [@team], dashboard.selected_teams
    end

    test "removes team from select teams if destroyed" do
      dashboard = create(:user_dashboard, user: @owner)
      destroy_team = create(:team, organization: @org)
      dashboard.selected_teams << destroy_team

      assert_changes -> { dashboard.selected_teams.count }, from: 1, to: 0 do
        destroy_team.destroy
      end
    end

    test "can't select more than 100 teams" do
      teams_to_add = 101.times.map { create(:team, organization: @org) }
      dashboard = create(:user_dashboard, user: @owner)
      dashboard.selected_teams = teams_to_add
      refute_predicate dashboard, :valid?
      assert_includes dashboard.errors[:selected_teams], "can't have more than 100 teams"
    end

    test "can only select teams the user can see" do
      dashboard = create(:user_dashboard, user: @owner)
      different_user = create(:user)
      different_org = create(:organization, admin: different_user)
      team = create(:team, organization: different_org)

      dashboard.selected_teams << team
      refute_predicate dashboard, :valid?
      assert_includes dashboard.errors[:selected_teams], "user must be able to view all selected teams"
    end

    test "traces prioritize_dependent! execution" do
      dashboard = create(:user_dashboard, user: @owner)
      shortcut = create(:search_shortcut, dashboard: dashboard)

      exporter.reset
      assert dashboard.prioritize_dependent!(shortcut, position: :top)

      span = find_span_by(name: "user_dashboard#prioritize_dependent!")

      refute_nil span
      assert_equal dashboard.id, span.attributes["context_id"]
      assert_equal dashboard.class.name, span.attributes["context_type"]
    end
  end
end
