# typed: true
# frozen_string_literal: true

require "test_helper"

module BusinessTeamHandlers
  class Test < GitHub::IntegrationTestCase
    include AuthenticationHelpers::SAML
    include DogstatsTestHelpers
    include GitHub::LoggerHelper
    include GitHub::ReactPayloadHelper
    include GitHub::LoggerHelper

    fixtures do
      @owner = create :user
      @business = create :business, owners: [@owner]
      @org = create :organization, :with_profile, profile_name: "A first org, NiCe", business: @business
      @org.description = "The first org being created."
      @org.save!
      @org2 = create :organization, login: "b-second-org-nice", business: @business
      @org3 = create :organization, :with_profile, profile_name: "C third org", business: @business
      @member = create :user
      @org.add_member(@member)

      create(:business_user_account, user: @owner, business: @business) if GitHub.single_business_environment?
    end

    setup do
      @business_team = create(:business_team, business: @business, name: "StackSquad", description: "Masters of the stack")
      as @owner

      enable_feature_flag(:enterprise_teams_crud, @business)
      disable_feature_flag(:esm_enabled)
      disable_feature_flag(:enterprise_teams_org_assignment)
      disable_feature_flag(:erp_staffship_enterprise_teams_org_assignment)
      disable_feature_flag(:erp_preview_enterprise_teams_org_assignment)
      disable_feature_flag(:enterprise_teams_enabled_for_organizations)
      disable_feature_flag(:business_user_account_filtered_members)
    end

    context "GET /enterprises/:slug/teams" do
      test "renders 404 when enterprise_teams_crud is disabled" do
        disable_feature_flag(:enterprise_teams_crud)
        disable_feature_flag(:erp_staffship_enterprise_teams_crud)
        disable_feature_flag(:erp_preview_enterprise_teams_crud)
        get "/enterprises/#{@business.slug}/teams"
        assert_response_not_found
      end

      test "renders 200 and renders react partial with correct props when enterprise_teams_crud is enabled" do
        get "/enterprises/#{@business.slug}/teams"

        assert_response_success
        assert_react_app("business-teams")

        assert_react_payload_equal(:enterprise_slug, @business.slug)
        assert_react_payload_equal(:enterprise_teams, [
          {
            "name" => @business_team.name,
            "id" => @business_team.id,
            "memberCount" => @business_team.member_ids.count,
            "slug" => @business_team.slug,
            "description" => @business_team.description,
            "viewTeamUrl" => enterprise_team_path(@business.slug, @business_team.slug, only_path: true),
            "editTeamUrl" => edit_enterprise_team_path(@business.slug, @business_team.slug, only_path: true),
          }
        ])
        assert_react_payload_equal(:create_team_url, new_enterprise_team_enterprise_path(@business.slug, only_path: true))
        assert_react_payload_equal(:total_teams_count, 1)
        assert_react_payload_equal(:is_owner, true)
        assert_react_payload_equal(:meta, {
          "filter" => "",
          "page" => 1,
          "pageSize" => 10,
          "sortOption" => "Name",
          "orderOption" => "Ascending"
        })
      end

      test "renders 200 and renders react partial with correct props for non-admin user" do
        as @member
        get "/enterprises/#{@business.slug}/teams"

        assert_response_success
        assert_react_app("business-teams")

        assert_react_payload_equal(:enterprise_slug, @business.slug)
        assert_react_payload_equal(:enterprise_teams, [
          {
            "name" => @business_team.name,
            "id" => @business_team.id,
            "memberCount" => @business_team.member_ids.count,
            "slug" => @business_team.slug,
            "description" => @business_team.description,
            "viewTeamUrl" => enterprise_team_path(@business.slug, @business_team.slug, only_path: true),
            "editTeamUrl" => edit_enterprise_team_path(@business.slug, @business_team.slug, only_path: true),
          }
        ])
        assert_react_payload_equal(:create_team_url, new_enterprise_team_enterprise_path(@business.slug, only_path: true))
        assert_react_payload_equal(:total_teams_count, 1)
        assert_react_payload_equal(:is_owner, false)
        assert_react_payload_equal(:meta, {
          "filter" => "",
          "page" => 1,
          "pageSize" => 10,
          "sortOption" => "Name",
          "orderOption" => "Ascending"
        })
      end

      test "sorted by name asc by default" do
        team_r = create(:business_team, business: @business, name: "Raptors")
        team_t = create(:business_team, business: @business, name: "Turtles")

        get "/enterprises/#{@business.slug}/teams"
        assert_response_success

        team_names = get_react_payload_value_from_keys(:enterprise_teams).pluck("name")
        assert_equal %w(Raptors StackSquad Turtles), team_names
      end

      test "sorted by name as when requested (asc by default)" do
        team_r = create(:business_team, business: @business, name: "Raptors")
        team_t = create(:business_team, business: @business, name: "Turtles")

        get "/enterprises/#{@business.slug}/teams", params: { sort: "Name" }
        assert_response_success

        team_names = get_react_payload_value_from_keys(:enterprise_teams).pluck("name")
        assert_equal %w(Raptors StackSquad Turtles), team_names
      end

      test "sorted by name as when requested (name by default)" do
        team_r = create(:business_team, business: @business, name: "Raptors")
        team_t = create(:business_team, business: @business, name: "Turtles")

        get "/enterprises/#{@business.slug}/teams", params: { order: "Ascending" }
        assert_response_success

        team_names = get_react_payload_value_from_keys(:enterprise_teams).pluck("name")
        assert_equal %w(Raptors StackSquad Turtles), team_names
      end

      test "sorted by name asc" do
        team_r = create(:business_team, business: @business, name: "Raptors")
        team_t = create(:business_team, business: @business, name: "Turtles")

        get "/enterprises/#{@business.slug}/teams", params: { sort: "Name", order: "Ascending" }
        assert_response_success

        team_names = get_react_payload_value_from_keys(:enterprise_teams).pluck("name")
        assert_equal %w(Raptors StackSquad Turtles), team_names
      end

      test "sorted by name desc" do
        team_r = create(:business_team, business: @business, name: "Raptors")
        team_t = create(:business_team, business: @business, name: "Turtles")

        get "/enterprises/#{@business.slug}/teams", params: { sort: "Name", order: "Descending" }
        assert_response_success

        team_names = get_react_payload_value_from_keys(:enterprise_teams).pluck("name")
        assert_equal %w(Turtles StackSquad Raptors), team_names
      end

      test "sorted by last added (asc by default)" do
        team_r = create(:business_team, business: @business, name: "Raptors", created_at: -1.day.ago)
        team_t = create(:business_team, business: @business, name: "Turtles", created_at: -2.days.ago)

        get "/enterprises/#{@business.slug}/teams", params: { sort: "Last added" }
        assert_response_success

        team_names = get_react_payload_value_from_keys(:enterprise_teams).pluck("name")
        assert_equal %w(StackSquad Raptors Turtles), team_names
      end

      test "sorted by last added asc" do
        team_r = create(:business_team, business: @business, name: "Raptors", created_at: -1.day.ago)
        team_t = create(:business_team, business: @business, name: "Turtles", created_at: -2.days.ago)

        get "/enterprises/#{@business.slug}/teams", params: { sort: "Last added", order: "Ascending" }
        assert_response_success

        team_names = get_react_payload_value_from_keys(:enterprise_teams).pluck("name")
        assert_equal %w(StackSquad Raptors Turtles), team_names
      end

      test "sorted by last added desc" do
        team_r = create(:business_team, business: @business, name: "Raptors", created_at: -1.day.ago)
        team_t = create(:business_team, business: @business, name: "Turtles", created_at: -2.days.ago)

        get "/enterprises/#{@business.slug}/teams", params: { sort: "Last added", order: "Descending" }
        assert_response_success

        team_names = get_react_payload_value_from_keys(:enterprise_teams).pluck("name")
        assert_equal %w(Turtles Raptors StackSquad), team_names
      end
    end

    context "GET /enterprises/:slug/new_team" do
      test "renders 404 for when disabled" do
        disable_feature_flag(:enterprise_teams_crud)
        disable_feature_flag(:erp_staffship_enterprise_teams_crud)
        disable_feature_flag(:erp_preview_enterprise_teams_crud)
        get "/enterprises/#{@business.slug}/new_team"
        assert_response_not_found
      end

      test "renders 404 if the business doesn't exist" do
        disable_feature_flag(:enterprise_teams_crud)
        disable_feature_flag(:erp_staffship_enterprise_teams_crud)
        disable_feature_flag(:erp_preview_enterprise_teams_crud)
        get "/enterprises/not-a-business/new_team"

        assert_response_not_found
      end

      test "renders the correct payload and react app when enterprise_teams_crud enabled" do
        disable_feature_flag(:enterprise_teams_org_assignment)
        disable_feature_flag(:erp_staffship_enterprise_teams_org_assignment)
        disable_feature_flag(:erp_preview_enterprise_teams_org_assignment)
        disable_feature_flag(:enterprise_teams_forbid_edit_form_org_selection)
        disable_feature_flag(:erp_staffship_enterprise_teams_forbid_edit_form_org_selection)
        disable_feature_flag(:erp_preview_enterprise_teams_forbid_edit_form_org_selection)
        get "/enterprises/#{@business.slug}/new_team"

        assert_response_success
        assert_react_app("business-teams")
        assert_react_payload_equal(:enterprise_slug, @business.slug)
        assert_react_payload_equal(:canSelectAllOrganizations, false)
        assert_react_payload_equal(:canSelectOrganizationAssignmentType, false)
        assert_react_payload_nil(:enterprise_team)
        assert_react_payload_equal(:all_orgs_count, @business.organizations.count)
        assert_react_payload_equal(:preventEditOrganizations, false)
      end

      test "preventEditOrganizations is always false for new team, even when feature flag is enabled" do
        disable_feature_flag(:enterprise_teams_org_assignment)
        disable_feature_flag(:erp_staffship_enterprise_teams_org_assignment)
        disable_feature_flag(:erp_preview_enterprise_teams_org_assignment)
        enable_feature_flag(:enterprise_teams_forbid_edit_form_org_selection)

        get "/enterprises/#{@business.slug}/new_team"

        assert_response_success
        assert_react_app("business-teams")
        assert_react_payload_equal(:preventEditOrganizations, false)
      end

      test "enables canSelectAllOrganizations when M2 FF is enabled" do
        enable_feature_flag(:enterprise_teams_org_assignment)
        get "/enterprises/#{@business.slug}/new_team"

        assert_response_success
        assert_react_app("business-teams")
        assert_react_payload_equal(:canSelectAllOrganizations, true)
        assert_react_payload_equal(:canSelectOrganizationAssignmentType, true)
      end

      context "authorization checks" do
        test "user is not owner" do
          member = create :user
          @org.add_member(member)

          as member
          get "/enterprises/#{@business.slug}/new_team"

          assert_response_not_found
        end

        test "user is not from the business" do
          rando = create :user
          as rando
          get "/enterprises/#{@business.slug}/new_team"

          assert_response_not_found
        end
      end
    end

    context "POST /enterprises/:slug/teams" do
      test "renders 404 for when disabled" do
        disable_feature_flag(:enterprise_teams_crud)
        disable_feature_flag(:erp_staffship_enterprise_teams_crud)
        disable_feature_flag(:erp_preview_enterprise_teams_crud)
        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: "TnT Team",
          teamDescription: "Testing",
          organizationSelectionType: :disabled
        }
        assert_response_not_found
      end

      test "renders the correct payload and react app when enterprise_teams_crud enabled" do
        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: "TnT Team",
          teamDescription: "New business team",
          organizationSelectionType: "all",
          selectedOrganizationIds: "[]",
        }
        assert_response_success
        response_json = JSON.parse(response.body)
        assert_equal enterprise_team_path(slug: @business.slug, team_slug: "tnt-team"), response_json["data"]["redirect"]

        new_team = @business.business_teams.find_by(name: "TnT Team")
        refute_nil new_team
        new_team = T.must(new_team)
        assert_equal "TnT Team", new_team.name
        assert_equal "tnt-team", new_team.slug
        assert_equal "New business team", new_team.description
      end

      test "blocks usage of empty team name" do
        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: "",
        }
        assert_response_bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Name cannot be empty.", response_json["data"]["error"]
      end

      test "requires teamName parameter for new team" do
        post "/enterprises/#{@business.slug}/teams", params: {}
        assert_response_bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Name cannot be empty.", response_json["data"]["error"]
      end

      test "blocks usage of existing team name within Enterprise" do
        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: @business_team.name,
          teamDescription: "Duplicate name",
          organizationSelectionType: "all",
          selectedOrganizationIds: "[]",
        }

        assert_response :bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Name has already been taken", response_json["data"]["error"]
      end

      test "blocks usage of invalid team name within Enterprise" do
        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: "awesome-team 😀!",
          teamDescription: "A team name that includes emojis",
          organizationSelectionType: "all",
          selectedOrganizationIds: "[]",
        }

        assert_response :bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Name doesn't accept 4-byte Unicode", response_json["data"]["error"]
      end

      test "creates a team with all organizations" do
        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: "All team",
          teamDescription: "Access to all organizations",
          organizationSelectionType: "all",
        }

        assert_response_success
        new_team = @business.business_teams.find_by(name: "All team")
        refute_nil new_team
        assert_equal "all", new_team.organization_selection_type

        expected_orgs = @business.organization_ids
        assert_same_elements expected_orgs, new_team.organization_ids
      end

      test "creates a team with selected organizations" do
        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: "Acme Corp",
          teamDescription: "Best description ever",
          organizationSelectionType: "selected",
          selectedOrganizationIds: [@org.id, @org2.id].to_json,
        }

        assert_response_success
        new_team = @business.business_teams.find_by(name: "Acme Corp")
        refute_nil new_team
        assert_equal "selected", new_team.organization_selection_type
        assert_same_elements [@org.id, @org2.id], new_team.organization_ids
      end

      test "creates a team with no organizations (none selected)" do
        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: "Independent Team",
          teamDescription: "This team has no org access",
          organizationSelectionType: "disabled",
        }

        assert_response_success
        new_team = @business.business_teams.find_by(name: "Independent Team")
        refute_nil new_team
        assert_equal "disabled", new_team.organization_selection_type
        assert_empty new_team.organization_ids
      end

      test "returns error for invalid organizationSelectionType" do
        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: "Invalid Type Team",
          teamDescription: "I have an invalid org selection type",
          organizationSelectionType: "invalid_type",
        }

        assert_response_bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Invalid organization selection type.", response_json["data"]["error"]
      end
    end

    context "POST /enterprises/:slug/teams/:team_slug/members" do
      test "renders 404 when FF disabled" do
        team = create(:business_team, business: @business, name: "TeamOne", slug: "team-one")
        disable_feature_flag(:enterprise_teams_crud)
        disable_feature_flag(:erp_staffship_enterprise_teams_crud)
        disable_feature_flag(:erp_preview_enterprise_teams_crud)

        post "/enterprises/#{@business.slug}/teams/#{team.slug}/members", params: {
          user_ids: [@owner.id]
        }

        assert_response_not_found
        assert_equal [], @business_team.member_ids
      end

      test "adds provided user_ids" do
        users = (1..5).map do
          user = create :user
          @org.add_member(user)
          user
        end
        T.assert_type!(users, T::Array[User])
        perform_enqueued_jobs only: BusinessUserAccountUpdateAttributesJob

        post "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/members", as: :json, params: {
          user_ids: [users.first.id, users.second.id, users.third.id]
        }

        assert_response_success
        assert_equal 3, @business_team.member_ids.count
      end

      test "uses a background job to add large number of users" do
        users = (1..3).map do
          user = create :user
          @org.add_member(user)
          user
        end
        T.assert_type!(users, T::Array[User])
        perform_enqueued_jobs only: BusinessUserAccountUpdateAttributesJob

        assert_enqueued_with job: BusinessTeamsAddMembersJob do
          BusinessTeamHandlers.stub_const(:PER_PAGE, 2) do
            post "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/members", as: :json, params: {
              user_ids: [users.first.id, users.second.id, users.third.id]
            }
          end
        end

        assert_response_success
        assert_equal 2, @business_team.member_ids.count

        perform_enqueued_jobs only: BusinessTeamsAddMembersJob
        assert_same_elements [users.first, users.second, users.third], @business_team.members
      end

      test "adds all enterprise members when select_all_in_enterprise is true" do
        (1..5).each do
          user = create :user
          @org.add_member(user)
        end
        perform_enqueued_jobs only: BusinessUserAccountUpdateAttributesJob

        post "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/members", as: :json, params: {
          select_all_in_enterprise: true
        }

        assert_response_success
        assert_equal 10, @business_team.member_ids.count
      end
    end

    context "PUT /enterprises/:slug/teams/:team_slug" do
      test "renders 404 for when FF disabled" do
        team = create(:business_team, business: @business, name: "TeamOne", slug: "team-one")
        disable_feature_flag(:enterprise_teams_crud)
        disable_feature_flag(:erp_staffship_enterprise_teams_crud)
        disable_feature_flag(:erp_preview_enterprise_teams_crud)

        put "/enterprises/#{@business.slug}/teams/#{team.slug}", params: {
          teamName: "TnT Team",
          description: "Testing",
        }

        assert_response_not_found
      end

      test "correctly updates the team" do
        team = create(:business_team, business: @business, name: "TeamOne", slug: "team-one")

        put "/enterprises/#{@business.slug}/teams/#{team.slug}", params: {
          teamName: "TnT Team",
          teamDescription: "New business team",
          organizationSelectionType: "all",
          selectedOrganizationIds: "[]",
        }

        assert_response_success
        response_json = JSON.parse(response.body)
        assert_equal enterprise_team_path(slug: @business.slug, team_slug: "tnt-team"), response_json["data"]["redirect"]

        team.reload
        assert_equal "TnT Team", team.name
        assert_equal "tnt-team", team.slug
        assert_equal "New business team", team.description
      end

      test "cannot update team if not found" do
        put "/enterprises/#{@business.slug}/teams/ghost-team", params: {
          teamName: "TnT Team",
          teamDescription: "New business team",
          organizationSelectionType: "all",
          selectedOrganizationIds: "[]",
        }
        assert_response_not_found
        response_json = JSON.parse(response.body)
        assert_equal "Team not found.", response_json["data"]["error"]
      end

      test "blocks usage of empty team name" do
        team = create(:business_team, business: @business, name: "TeamOne", slug: "team-one")

        put "/enterprises/#{@business.slug}/teams/#{team.slug}", params: {
          teamName: "",
        }
        assert_response_bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Name cannot be empty.", response_json["data"]["error"]
      end

      test "requires teamName parameter for new team" do
        team = create(:business_team, business: @business, name: "TeamOne", slug: "team-one")

        put "/enterprises/#{@business.slug}/teams/#{team.slug}", params: {}
        assert_response_bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Name cannot be empty.", response_json["data"]["error"]
      end

      test "blocks usage of existing team name within Enterprise" do
        team = create(:business_team, business: @business, name: "TeamOne", slug: "team-one")

        put "/enterprises/#{@business.slug}/teams/#{team.slug}", params: {
          teamName: @business_team.name,
          teamDescription: "Duplicate name",
          organizationSelectionType: "all",
          selectedOrganizationIds: "[]",
        }

        assert_response :bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Name has already been taken", response_json["data"]["error"]
      end

      test "blocks usage of invalid team name within Enterprise" do
        team = create(:business_team, business: @business, name: "TeamOne", slug: "team-one")

        put "/enterprises/#{@business.slug}/teams/#{team.slug}", params: {
          teamName: "awesome-team 😀!",
          teamDescription: "A team name that includes emojis",
          organizationSelectionType: "all",
          selectedOrganizationIds: "[]",
        }

        assert_response :bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Name doesn't accept 4-byte Unicode", response_json["data"]["error"]
      end

      test "updates a team's organizationSelectionType from all to selected" do
        team = create(:business_team, business: @business, name: "Team all", organization_selection_type: "all")

        put "/enterprises/#{@business.slug}/teams/#{team.slug}", params: {
          teamName: "Team all updated",
          teamDescription: "Now has selected orgs",
          organizationSelectionType: "selected",
          selectedOrganizationIds: [@org.id, @org2.id].to_json,
        }

        assert_response_success
        team.reload
        assert_equal "selected", team.organization_selection_type
        assert_same_elements [@org.id, @org2.id], team.organization_ids
      end

      test "updates a team's organizationSelectionType from selected to all" do
        team = create(:business_team, business: @business, name: "Team selected", organization_selection_type: "selected")

        team.business_team_org_assignments.create!(organization: @org)
        team.business_team_org_assignments.create!(organization: @org2)

        assert_equal 2, team.business_team_org_assignments.count

        put "/enterprises/#{@business.slug}/teams/#{team.slug}", params: {
          teamName: "Team selected updated",
          teamDescription: "Now has access to all orgs",
          organizationSelectionType: "all",
        }

        assert_response_success
        team.reload
        assert_equal "all", team.organization_selection_type
        assert_same_elements @business.organization_ids, team.organization_ids
        assert_empty team.business_team_org_assignments
      end

      test "updates a team's organizationSelectionType from selected to all, with a soft deleted org", skip_enterprise: true do
        org4 = create :organization, business: @business

        team = create(:business_team, business: @business, name: "Team selected", organization_selection_type: "selected")

        team.business_team_org_assignments.create!(organization: @org)
        team.business_team_org_assignments.create!(organization: @org2)
        team.business_team_org_assignments.create!(organization: org4)

        org4.soft_delete!

        assert_equal 3, team.business_team_org_assignments.count
        assert_equal 2, team.selected_organization_ids.count

        put "/enterprises/#{@business.slug}/teams/#{team.slug}", params: {
          teamName: "Team selected updated",
          teamDescription: "Now has access to all orgs",
          organizationSelectionType: "all",
        }

        assert_response_success
        team.reload
        assert_equal "all", team.organization_selection_type
        assert_same_elements @business.organization_ids, team.organization_ids
        assert_empty team.business_team_org_assignments
      end

      test "updates a team's organizationSelectionType from selected to none" do
        team = create(:business_team, business: @business, name: "Team selected", organization_selection_type: "selected")

        team.business_team_org_assignments.create!(organization: @org)
        team.business_team_org_assignments.create!(organization: @org2)

        assert_equal 2, team.business_team_org_assignments.count

        put "/enterprises/#{@business.slug}/teams/#{team.slug}", params: {
          teamName: "Team selected updated",
          teamDescription: "Now has no orgs",
          organizationSelectionType: "disabled",
        }

        assert_response_success
        team.reload
        assert_equal "disabled", team.organization_selection_type
        assert_empty team.organization_ids
        assert_empty team.business_team_org_assignments
      end

      test "returns error when updating a non-existent team" do
        put "/enterprises/#{@business.slug}/teams/non-existent-team", params: {
          teamName: "Ghost Team",
          teamDescription: "I don't exist",
          organizationSelectionType: "selected",
          selectedOrganizationIds: [].to_json,
        }

        assert_response :not_found
        response_json = JSON.parse(response.body)
        assert_equal "Team not found.", response_json["data"]["error"]
      end

      test "returns error when updating team with invalid organizationSelectionType" do
        team = create(:business_team, business: @business, name: "I will be updated", organization_selection_type: "selected")

        put "/enterprises/#{@business.slug}/teams/#{team.slug}", params: {
          teamName: "I am updated",
          teamDescription: "Trying to update with an invalid org selection type",
          organizationSelectionType: "invalid_type",
        }

        assert_response :bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Invalid organization selection type.", response_json["data"]["error"]
      end
    end

    context "GET /enterprises/:slug/teams/:team_slug/edit" do
      test "renders 404 for when disabled" do
        disable_feature_flag(:enterprise_teams_crud)
        disable_feature_flag(:erp_staffship_enterprise_teams_crud)
        disable_feature_flag(:erp_preview_enterprise_teams_crud)
        get "/enterprises/#{@business.slug}/new_team"
        assert_response_not_found
      end

      test "renders the correct payload and react app when enterprise_teams_crud enabled" do
        disable_feature_flag(:enterprise_teams_org_assignment)
        disable_feature_flag(:erp_staffship_enterprise_teams_org_assignment)
        disable_feature_flag(:erp_preview_enterprise_teams_org_assignment)
        disable_feature_flag(:enterprise_teams_forbid_edit_form_org_selection)
        disable_feature_flag(:erp_staffship_enterprise_teams_forbid_edit_form_org_selection)
        disable_feature_flag(:erp_preview_enterprise_teams_forbid_edit_form_org_selection)
        get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/edit"

        assert_response_success
        assert_react_app("business-teams")
        assert_react_payload_equal(:enterprise_slug, @business.slug)
        assert_react_payload_equal(:all_orgs_count, @business.organizations.count)
        assert_react_payload_equal(:canSelectAllOrganizations, false)
        assert_react_payload_equal(:canSelectOrganizationAssignmentType, false)
        assert_react_payload_equal(:preventEditOrganizations, false)
        assert_react_payload_equal(:enterprise_team, {
            "name" => @business_team.name,
            "slug" => @business_team.slug,
            "description" => @business_team.description,
            "organizationSelectionType" => "selected",
            "url" => "/enterprises/#{@business.slug}/teams/#{@business_team.slug}",
            "selectedOrganizations" => [],
          }
        )
      end

      test "does not allow editing organizations when feature flag is enabled" do
        disable_feature_flag(:enterprise_teams_org_assignment)
        disable_feature_flag(:erp_staffship_enterprise_teams_org_assignment)
        disable_feature_flag(:erp_preview_enterprise_teams_org_assignment)
        enable_feature_flag(:enterprise_teams_forbid_edit_form_org_selection)

        get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/edit"

        assert_response_success
        assert_react_app("business-teams")
        assert_react_payload_equal(:preventEditOrganizations, true)
      end

      test "enables canSelectAllOrganizations when M2 FF is enabled" do
        enable_feature_flag(:enterprise_teams_org_assignment)
        get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/edit"

        assert_response_success
        assert_react_app("business-teams")
        assert_react_payload_equal(:canSelectAllOrganizations, true)
        assert_react_payload_equal(:canSelectOrganizationAssignmentType, true)
      end

      %w(all disabled).each do |type|
        test "does not render selected organizations at all when type is #{type}" do
          enable_feature_flag(:enterprise_teams_org_assignment)
          @business_team.organization_selection_type = type
          @business_team.save!

          get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/edit"
          assert_response_success

          assert_react_payload_equal(:enterprise_team, {
            "name" => @business_team.name,
            "slug" => @business_team.slug,
            "description" => @business_team.description,
            "organizationSelectionType" => type,
            "url" => "/enterprises/#{@business.slug}/teams/#{@business_team.slug}"
          }
        )
        end
      end

      test "renders selected organizations" do
        enable_feature_flag(:enterprise_teams_org_assignment)
        @business_team.add_to_organizations(org_ids: [@org, @org2, @org3])

        get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/edit"
        assert_response_success

        assert_react_payload_equal(:enterprise_team, {
            "name" => @business_team.name,
            "slug" => @business_team.slug,
            "description" => @business_team.description,
            "organizationSelectionType" => "selected",
            "url" => "/enterprises/#{@business.slug}/teams/#{@business_team.slug}",
            "selectedOrganizations" => [
              {
                "id" => @org.id,
                "name" => @org.profile_name,
                "description" => @org.description,
                "avatarUrl" => @org.primary_avatar_url
              },
              {
                "id" => @org2.id,
                "name" => @org2.display_login,
                "description" => nil,
                "avatarUrl" => @org2.primary_avatar_url
              },
              {
                "id" => @org3.id,
                "name" => @org3.profile_name,
                "description" => nil,
                "avatarUrl" => @org3.primary_avatar_url
              },
            ],
          }
        )
      end

      context "authorization checks" do
        test "user is not owner" do
          member = create :user
          @org.add_member(member)
          as member
          get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/edit"

          assert_response_not_found
        end

        test "user is not from the business" do
          rando = create :user
          as rando
          get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/edit"

          assert_response_not_found
        end
      end
    end

    context "DELETE /enterprises/:slug/teams/bulk_delete" do
      test "renders 404 when enterprise_teams_crud is disabled" do
        disable_feature_flag(:enterprise_teams_crud)
        disable_feature_flag(:erp_staffship_enterprise_teams_crud)
        disable_feature_flag(:erp_preview_enterprise_teams_crud)
        delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: { team_slugs: [@business_team.slug] }
        assert_response_not_found
      end

      test "renders 404 if the business doesn't exist" do
        disable_feature_flag(:enterprise_teams_crud)
        disable_feature_flag(:erp_staffship_enterprise_teams_crud)
        disable_feature_flag(:erp_preview_enterprise_teams_crud)
        delete "/enterprises/not-a-business/teams/bulk_delete", params: { team_slugs: [@business_team.slug] }
        assert_response_not_found
      end

      test "deletes the business team when enterprise_teams_crud is enabled" do
        delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: { team_slugs: [@business_team.slug] }
        assert_response_success
        response_json = JSON.parse(response.body)
        assert_equal enterprise_teams_url(@business), response_json["data"]["redirect"]

        deleted_team = @business.business_teams.find_by(slug: @business_team.slug)
        assert_nil deleted_team
      end

      test "renders 404 if the team does not exist" do
        delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: { team_slugs: ["non-existent-team"] }
        assert_response_not_found
        response_json = JSON.parse(response.body)
        assert_equal "No team found.", response_json["data"]["error"]
      end

      test "deletes multiple business teams when enterprise_teams_crud is enabled" do
        team1 = create(:business_team, business: @business, name: "TeamOne", slug: "team-one")
        team2 = create(:business_team, business: @business, name: "TeamTwo", slug: "team-two")

        delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: { team_slugs: [team1.slug, team2.slug] }
        assert_response_success
        response_json = JSON.parse(response.body)
        assert_equal enterprise_teams_url(@business), response_json["data"]["redirect"]

        deleted_team1 = @business.business_teams.find_by(slug: team1.slug)
        deleted_team2 = @business.business_teams.find_by(slug: team2.slug)
        assert_nil deleted_team1
        assert_nil deleted_team2
      end

      test "renders 404 if one of the teams does not exist when deleting multiple teams" do
        team1 = create(:business_team, business: @business, name: "TeamOne", slug: "team-one")

        delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: { team_slugs: [team1.slug, "non-existent-team"] }
        assert_response_not_found
        response_json = JSON.parse(response.body)
        assert_equal "One or more teams not found", response_json["data"]["error"]

        deleted_team1 = @business.business_teams.find_by(slug: team1.slug)
        refute_nil deleted_team1
      end

      context "authorization checks" do
        test "user is not owner" do
          member = create :user
          @org.add_member(member)
          as member
          delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: { team_slugs: [@business_team.slug] }
          assert_response_not_found
        end

        test "user is not from the business" do
          rando = create :user
          as rando
          delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: { team_slugs: [@business_team.slug] }
          assert_response_not_found
        end
      end
    end

    private def setup_users_for_sort_test
      @bob = create :user, login: "bob-longname"
      @bob.profile_name = nil
      @bob.save!
      create(:business_user_account, user: @bob, business: @business)

      @zoe = create :user, login: "zoe-longname"
      @zoe.profile_name = "Zoe longname"
      @zoe.save!
      create(:business_user_account, user: @zoe, business: @business)

      @org.add_member(@bob)
      @org.add_member(@zoe)
      @business_team.bulk_add_members([@bob, @zoe], caller_type: :business_team)
    end

    context "GET /enterprises/:slug/teams/:team_slug/members" do
      test "renders 404 when enterprise_teams_crud is disabled" do
        disable_feature_flag(:enterprise_teams_crud)
        disable_feature_flag(:erp_staffship_enterprise_teams_crud)
        disable_feature_flag(:erp_preview_enterprise_teams_crud)
        get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}"
        assert_response_not_found

        get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/members"
        assert_response_not_found
      end

      test "returns 404 if team not found" do
        get "/enterprises/#{@business.slug}/teams/imaginary_team"
        assert_response_not_found

        get "/enterprises/#{@business.slug}/teams/imaginary_team/members"
        assert_response_not_found
      end

      test "returns 404 for non-owner member" do
        member = create :user
        @org.add_member(member)

        as member
        get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/members"
        assert_response_not_found
      end

      test "renders json if request.xhr?" do
        user1 = create :user
        user1.profile_name = "A User"
        user1.save!
        create(:business_user_account, user: user1, business: @business)

        user2 = create :user
        user2.profile_name = nil
        user2.save!
        create(:business_user_account, user: user2, business: @business)

        @org.add_member(user1)
        @org.add_member(user2)
        @business_team.bulk_add_members([user1, user2], caller_type: :business_team)

        get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/members", xhr: true

        assert_response_success
        json = JSON.parse(response.body)
        assert_equal json["enterpriseTeam"], {
            "name" => @business_team.name,
            "slug" => @business_team.slug,
            "description" => @business_team.description,
            "totalMemberCount" => 2,
            "totalOrganizationCount" => 0,
            "totalRoleCount" => 0
          }
        assert_equal json["meta"], {
          "filter" => "",
          "page" => 1,
          "pageSize" => 30,
          "sortOption" => "Name",
          "orderOption" => "Ascending",
          "queryMemberCount" => 2,
          "membersAllowedToAdd" => @business_team.limit_members_in_team - 2,
          "memberLimitReached" => false
        }
        assert_same_elements([
          {
            "displayLogin" => user1.display_login,
            "profileName" => "A User",
            "id" => user1.id,
            "avatarUrl" => user1.primary_avatar_url
          },
          {
            "displayLogin" => user2.display_login,
            "profileName" => user2.display_login,
            "id" => user2.id,
            "avatarUrl" => user2.primary_avatar_url
          },
        ], json["members"])
      end

      test "renders list of members" do
        user1 = create :user
        user1.profile_name = "A User"
        user1.save!
        create(:business_user_account, user: user1, business: @business)

        user2 = create :user
        user2.profile_name = nil
        user2.save!
        create(:business_user_account, user: user2, business: @business)

        @org.add_member(user1)
        @org.add_member(user2)
        @business_team.bulk_add_members([user1, user2], caller_type: :business_team)

        get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/members"

        assert_response_success
        assert_react_app("business-teams")
        assert_react_payload_equal(:enterprise_slug, @business.slug)
        assert_react_payload_equal(:enterprise_team,
          {
            "name" => @business_team.name,
            "slug" => @business_team.slug,
            "description" => @business_team.description,
            "totalMemberCount" => 2,
            "totalOrganizationCount" => 0,
            "totalRoleCount" => 0
          })
        assert_react_payload_equal(:meta, {
          "filter" => "",
          "page" => 1,
          "pageSize" => 30,
          "sortOption" => "Name",
          "orderOption" => "Ascending",
          "queryMemberCount" => 2,
          "membersAllowedToAdd" => @business_team.limit_members_in_team - 2,
          "memberLimitReached" => false
        })
        member_data = get_react_payload_value_from_keys(:members)
        assert_same_elements([
          {
            "displayLogin" => user1.display_login,
            "profileName" => "A User",
            "id" => user1.id,
            "avatarUrl" => user1.primary_avatar_url
          },
          {
            "displayLogin" => user2.display_login,
            "profileName" => user2.display_login,
            "id" => user2.id,
            "avatarUrl" => user2.primary_avatar_url
          },
        ], member_data)

        # check alias url is the same result
        payload = get_react_embedded_json
        get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}"
        assert_response_success
        assert_equal payload, get_react_embedded_json
      end

      test "member list is sorted by name asc by default" do
        setup_users_for_sort_test

        get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/members"
        assert_response_success

        assert_react_payload_equal(:members, [
          {
            "displayLogin" => @bob.display_login,
            "profileName" => @bob.display_login,
            "id" => @bob.id,
            "avatarUrl" => @bob.primary_avatar_url
          },
          {
            "displayLogin" => @zoe.display_login,
            "profileName" => @zoe.profile_name,
            "id" => @zoe.id,
            "avatarUrl" => @zoe.primary_avatar_url
          },
        ])
      end

      test "member list is sorted by name asc when requested" do
        setup_users_for_sort_test

        get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/members", params: { order: "Ascending" }
        assert_response_success

        assert_react_payload_equal(:members, [
          {
            "displayLogin" => @bob.display_login,
            "profileName" => @bob.display_login,
            "id" => @bob.id,
            "avatarUrl" => @bob.primary_avatar_url
          },
          {
            "displayLogin" => @zoe.display_login,
            "profileName" => @zoe.profile_name,
            "id" => @zoe.id,
            "avatarUrl" => @zoe.primary_avatar_url
          },
        ])
      end

      test "member list is sorted by name desc when requested" do
        setup_users_for_sort_test

        get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/members", params: { order: "Descending" }
        assert_response_success

        assert_react_payload_equal(:members, [
          {
            "displayLogin" => @zoe.display_login,
            "profileName" => @zoe.profile_name,
            "id" => @zoe.id,
            "avatarUrl" => @zoe.primary_avatar_url
          },
          {
            "displayLogin" => @bob.display_login,
            "profileName" => @bob.display_login,
            "id" => @bob.id,
            "avatarUrl" => @bob.primary_avatar_url
          },
        ])
      end

      test "search by user name" do
        setup_users_for_sort_test

        get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/members", params: { query: "zoe-longname" }
        assert_response_success

        assert_react_payload_equal(:members, [
          {
            "displayLogin" => @zoe.display_login,
            "profileName" => @zoe.profile_name,
            "id" => @zoe.id,
            "avatarUrl" => @zoe.primary_avatar_url
          },
        ])
      end

      test "search by login" do
        setup_users_for_sort_test

        get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/members", params: { query: "bob-longname" }
        assert_response_success

        assert_react_payload_equal(:members, [
          {
            "displayLogin" => @bob.display_login,
            "profileName" => @bob.display_login,
            "id" => @bob.id,
            "avatarUrl" => @bob.primary_avatar_url
          },
        ])
      end
    end

    context "DELETE /enterprises/:slug/teams/:team_slug/members/bulk_delete" do
      test "renders 404 when enterprise_teams_crud is disabled" do
        disable_feature_flag(:enterprise_teams_crud)
        disable_feature_flag(:erp_staffship_enterprise_teams_crud)
        disable_feature_flag(:erp_preview_enterprise_teams_crud)
        delete "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/members/bulk_delete", params: {
          user_ids: []
        }
        assert_response_not_found
      end

      test "returns 404 if team not found" do
        delete "/enterprises/#{@business.slug}/teams/imaginary_team/members/bulk_delete", params: {
          user_ids: []
        }, xhr: true

        assert_response_not_found
        response_json = JSON.parse(response.body)
        assert_equal "Team not found.", response_json["data"]["error"]
      end

      test "remove users from the team (invalid users ignored)" do
        user = create :user
        create(:business_user_account, user: user, business: @business)

        @org.add_member(user)
        @business_team.bulk_add_members([@owner, user], caller_type: :business_team)
        non_org_user = create :user

        assert @business_team.members.include?(@owner)
        assert @business_team.members.include?(user)

        delete "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/members/bulk_delete", params: {
          user_ids: [@owner.id, user.id, -1, non_org_user.id]
        }

        assert_response_success
        response_json = JSON.parse(response.body)
        assert_equal enterprise_team_members_path(@business), response_json["data"]["redirect"]

        refute @business_team.members.include?(@owner)
        refute @business_team.members.include?(user)
      end
    end
  end
end
