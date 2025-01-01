# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessTeamsEligibleOrgControllerTest < GitHub::IntegrationTestCase
  extend T::Helpers
  include BusinessTestHelpers

  setup do
    set_business_teams_feature_flags
  end

  fixtures do
    @owner = create :user
    @user = create :user
    @business = create(:business, owners: [@owner])
    @org1 = create :organization, :with_profile, profile_name: "A first org, NiCe", business: @business, admins: [@owner], public_members: [@user]
    @org1.description = "The first org being created."
    @org1.save!
    @org2 = create :organization, login: "b-second-org-nice", business: @business, admins: [@owner], public_members: [@user]
    @org3 = create :organization, :with_profile, profile_name: "C third org", business: @business, admins: [@owner], public_members: [@user]
    @business_team = create :business_team, business: @business
  end

  context "validation" do
    test "returns 404 if business teams not enabled" do
      disable_feature_flag(:enterprise_teams_org_assignment)
      disable_feature_flag(:erp_preview)
      disable_feature_flag(:erp_staffship)

      as @owner
      post "/enterprises/#{@business.slug}/organization_suggestions", params: {}.to_json

      assert_response_not_found
    end

    test "returns 404 if not owner" do
      as @user
      post "/enterprises/#{@business.slug}/organization_suggestions", params: {}.to_json

      assert_response_not_found
    end

    test "returns 400 if no body" do
      as @owner
      post "/enterprises/#{@business.slug}/organization_suggestions"

      assert_response_bad_request
    end

    test "returns 400 if invalid selectedOrganizationIds" do
      as @owner

      post "/enterprises/#{@business.slug}/organization_suggestions", params: { selectedOrganizationIds: "invalid" }.to_json
      assert_response_bad_request

      post "/enterprises/#{@business.slug}/organization_suggestions", params: { selectedOrganizationIds: %w(1 2) }.to_json
      assert_response_bad_request
    end
  end

  context "queries" do
    test "returns first PER_PAGE suggestions" do
      BusinessTeamHandlers.stub_const(:PER_PAGE, 2) do
        as @owner
        post "/enterprises/#{@business.slug}/organization_suggestions", params: {}.to_json

        assert_response :success
        body = JSON.parse(response.body)
        assert_equal(@business.organizations.count, body["totalAvailableCount"])
        orgs = body["organizations"]
        assert_equal(2, orgs.count)

        assert_equal(@org1.id, orgs[0]["id"])
        assert_equal(@org1.profile_name, orgs[0]["name"])
        assert_equal(@org1.description, orgs[0]["description"])
        assert_equal(@org1.primary_avatar_url, orgs[0]["avatarUrl"])

        assert_equal(@org2.id, orgs[1]["id"])
        assert_equal(@org2.display_login, orgs[1]["name"])
        assert_nil orgs[1]["description"]
        assert_equal(@org2.primary_avatar_url, orgs[1]["avatarUrl"])
      end
    end

    test "queries by org display name" do
      as @owner
      post "/enterprises/#{@business.slug}/organization_suggestions", params: { query: "nIcE" }.to_json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal(@business.organizations.count, body["totalAvailableCount"])
      orgs = body["organizations"]
      assert_equal(2, orgs.count)

      assert_equal(@org1.id, orgs[0]["id"])
      assert_equal(@org1.profile_name, orgs[0]["name"])
      assert_equal(@org1.description, orgs[0]["description"])
      assert_equal(@org1.primary_avatar_url, orgs[0]["avatarUrl"])

      assert_equal(@org2.id, orgs[1]["id"])
      assert_equal(@org2.display_login, orgs[1]["name"])
      assert_nil orgs[1]["description"]
      assert_equal(@org2.primary_avatar_url, orgs[1]["avatarUrl"])
    end

    test "exclude orgs" do
      as @owner
      post "/enterprises/#{@business.slug}/organization_suggestions", params: { selectedOrganizationIds: [@org1.id, @org2.id] }.to_json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal(@business.organizations.count - 2, body["totalAvailableCount"])
      orgs = body["organizations"]
      assert_equal(@business.organizations.count - 2, orgs.count)

      assert_equal(@org3.id, orgs[0]["id"])
      assert_equal(@org3.profile_name, orgs[0]["name"])
      assert_nil orgs[0]["description"]
      assert_equal(@org3.primary_avatar_url, orgs[0]["avatarUrl"])
    end

    test "combine query" do
      as @owner
      post "/enterprises/#{@business.slug}/organization_suggestions", params: { query: "nIcE", selectedOrganizationIds: [@org2.id, @org3.id] }.to_json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal(@business.organizations.count - 2, body["totalAvailableCount"])
      orgs = body["organizations"]
      assert_equal(1, orgs.count)

      assert_equal(@org1.id, orgs[0]["id"])
      assert_equal(@org1.profile_name, orgs[0]["name"])
      assert_equal(@org1.description, orgs[0]["description"])
      assert_equal(@org1.primary_avatar_url, orgs[0]["avatarUrl"])
    end
  end
end
