# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamNavigationTabsTest < GitHub::TestCase
  fixtures do
    @team = create(:team)
    @user = create(:user)
  end

  setup do
    @organization = @team.organization
    @tabs_builder = Team::NavigationTabs.new(team: @team, current_user: @user)
  end

  def base_team_path
    "/orgs/#{@organization.name}/teams/#{@team.name}"
  end

  context "#tabs" do
    test "it renders tabs in the expected order" do
      GitHub.flipper[:team_discussions_disabled].disable
      GitHub.flipper[:enhanced_team_posts].disable
      @organization.stubs(:advanced_security_purchased?).returns(true)
      @organization.stubs(:adminable_by?).with(@user).returns(true)
      @team.stubs(:adminable_by?).with(@user).returns(true)

      assert_equal @tabs_builder.tabs.map(&:text), ["Members", "Teams", "Repositories", "Projects", "Organization roles", "Settings"]
    end

    test "it doesn't render the teams or settings tab for an enterprise managed team" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      GitHub.flipper[:team_discussions_disabled].disable
      GitHub.flipper[:enhanced_team_posts].disable
      @organization.stubs(:advanced_security_purchased?).returns(true)
      @organization.stubs(:adminable_by?).with(@user).returns(true)

      et = create :enterprise_team
      EnterpriseTeamOrganizationMapping.create(team: @team, organization: @organization, enterprise_team: et)

      assert_equal @tabs_builder.tabs.map(&:text), ["Members", "Repositories", "Projects", "Organization roles"]
    end unless GitHub.single_business_environment?

    test "it does not return nil values for tabs that do not apply to the team/user" do
      GitHub.flipper[:team_discussions_disabled].disable
      GitHub.flipper[:enhanced_team_posts].disable
      assert_equal @tabs_builder.tabs.map(&:text), %w[Members Teams Repositories Projects]
    end
  end

  context "#members_tab" do
    test "it returns a tab with the correct attributes" do
      member_count = 15
      @team.stubs(:members_scope_count).returns(member_count)
      tab = @tabs_builder.members_tab

      assert_equal "Members", tab.text
      assert_equal :person, tab.icon
      assert_equal :members, tab.highlight
      assert_equal "#{base_team_path}/members", tab.href
      assert_equal member_count, tab.count
    end
  end

  context "#teams_tab" do
    test "it returns nil when team is externally managed" do
      @team.stubs(:externally_managed?).returns(true)
      assert_nil @tabs_builder.teams_tab
    end

    test "it returns a tab with the correct attributes" do
      @team.stubs(:descendants).returns(["team 1", "team 2", "teams 3"])
      tab = @tabs_builder.teams_tab

      assert_equal "Teams", tab.text
      assert_equal :people, tab.icon
      assert_equal :teams, tab.highlight
      assert_equal "#{base_team_path}/teams", tab.href
      assert_equal 3, tab.count
    end
  end

  context "#repositories_tab" do
    test "it returns a tab with the correct attributes" do
      @tabs_builder.stubs(:accessible_team_repository_ids_for_current_user).with(@user, @team, @organization).returns([1, 2, 3, 4, 5])
      tab = @tabs_builder.repositories_tab

      assert_equal "Repositories", tab.text
      assert_equal :repo, tab.icon
      assert_equal :repositories, tab.highlight
      assert_equal "#{base_team_path}/repositories", tab.href
      assert_equal 5, tab.count
    end

    context "count" do
      test "sets the repositories tab count if repositories_count is passed as an option" do
        tab = Team::NavigationTabs.new(team: @team, current_user: @user, repositories_count: 10).repositories_tab

        assert_equal 10, tab.count
      end

      test "does not memoize a nil value" do
        tabs_builder = Team::NavigationTabs.new(team: @team, current_user: @user, repositories_count: nil)
        tabs_builder.stubs(:accessible_team_repository_ids_for_current_user).with(@user, @team, @organization).returns([1, 2, 3, 4])

        tab = tabs_builder.repositories_tab
        assert_equal 4, tab.count
      end
    end
  end

  context "#projects_tab" do
    test "it returns a tab with the correct attributes" do
      tab = @tabs_builder.projects_tab

      assert_equal "Projects", tab.text
      assert_equal :table, tab.icon
      assert_equal :projects, tab.highlight
      assert_equal "#{base_team_path}/projects", tab.href
      assert_nil tab.count
    end
  end

  context "#settings_tab" do
    test "it returns nil when the user can not admin the team" do
      assert_nil @tabs_builder.settings_tab
    end

    test "it returns a tab with the correct attributes" do
      @team.stubs(:adminable_by?).with(@user).returns(true)
      @team.stubs(:descendants).returns(["team 1", "team 3"])
      tab = @tabs_builder.settings_tab

      assert_equal "Settings", tab.text
      assert_equal :gear, tab.icon
      assert_equal :settings, tab.highlight
      assert_equal "#{base_team_path}/edit", tab.href
      assert_equal 2, tab.count
    end
  end

  context "#custom_org_roles_tab" do
    test "it returns a tab with the correct link" do
      @organization.stubs(:adminable_by?).with(@user).returns(true)
      @team.stubs(:descendants).returns(["team 1", "team 3"])
      tab = @tabs_builder.custom_org_roles_tab

      assert_equal "Organization roles", tab.text
      assert_equal :organization, tab.icon
      assert_equal :organization, tab.highlight
      href = "/organizations/#{@organization.login}/settings/org_role_assignments?query=#{@team.slug}+is%3Ateam"
      assert_equal href, tab.href
    end
  end
end
