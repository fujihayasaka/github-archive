# typed: true
# frozen_string_literal: true

require "test_helper"

class Organizations::Settings::SecurityConfigurations::FilterSuggestionsControllerTest < GitHub::IntegrationTestCase
  fixtures do
    @random_user = create(:user, name: "random-user")
    @owner = create(:user, name: "org-owner")
    @org = create(:organization, admin: @owner)
    @member = create(:user, name: "org-member")
    @org.add_member(@member)
    @security_manager = create(:user, name: "org-security-manager")
    @org.add_member(@security_manager)
    @security_manager_team = create(:security_manager_team, organization: @org)
    @security_manager_team.add_member(@security_manager)
    @no_teams_org = create(:organization, admin: @owner)
  end

  context "#teams" do
    test "renders 404 for users who are not a memeber of the organization" do
      as @random_user
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/filter-suggestions/teams"

      assert_response :not_found
    end

    test "renders 404 for org members who don't have access" do
      as @member
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/filter-suggestions/teams"

      assert_response :not_found
    end

    test "returns teams for the organization" do
      as @security_manager

      get "/organizations/#{@org.display_login}/settings/security_products/configurations/filter-suggestions/teams", params: { filter_value: "" }

      assert_response :ok
      json = JSON.parse(response.body)

      assert_equal 1, json["teams"].size
      assert_equal @security_manager_team.name, json["teams"].sole.fetch("name")
      assert_equal @security_manager_team.combined_slug, json["teams"].sole.fetch("slug")
      assert_equal @security_manager_team.primary_avatar_url(60), json["teams"].sole.fetch("avatar_url")
    end

    test "returns teams that match the query for the organization" do
      as @security_manager

      get "/organizations/#{@org.display_login}/settings/security_products/configurations/filter-suggestions/teams", params: { filter_value: "team-" }

      assert_response :ok
      json = JSON.parse(response.body)

      assert_equal 1, json["teams"].size
      assert_equal @security_manager_team.name, json["teams"].sole.fetch("name")
    end

    test "does not returns teams that don't match the query for the organization" do
      as @security_manager

      get "/organizations/#{@org.display_login}/settings/security_products/configurations/filter-suggestions/teams", params: { filter_value: "not-a-team" }

      assert_response :ok
      json = JSON.parse(response.body)

      assert_empty json.fetch("teams")
    end
  end
end
