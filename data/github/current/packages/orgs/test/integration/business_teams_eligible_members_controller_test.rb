# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessTeamsEligibleMembersControllerTest < GitHub::IntegrationTestCase
  extend T::Helpers
  include BusinessTestHelpers

  setup do
    set_business_teams_feature_flags
  end

  fixtures do
    @owner = create :user
    @user = create :user
    @business = create(:business, owners: [@owner])
    enable_feature_flag(:enterprise_teams_crud, @business)
    @org = create :organization, business: @business, admins: [@owner], public_members: [@user]
    @business_team = create :business_team, business: @business
    perform_enqueued_jobs only: BusinessUserAccountUpdateAttributesJob
  end

  context "GET" do
    test "returns eligible members" do
      as @owner
      get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/eligible_members", format: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal(2, body["users"].count)
      assert_equal(2, body["totalEligibleUsersInEnterprise"])
    end

    test "does not return members of the team" do
      @business_team.add_member(@owner, caller_type: :business_team)

      as @owner
      get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/eligible_members", format: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal(1, body["users"].count)
      assert_equal(1, body["totalEligibleUsersInEnterprise"])
    end

    test "returns filtered members when a query is provided" do
      as @owner
      get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/eligible_members?query=#{@owner.display_login}", format: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal(1, body["users"].count)
      assert_equal(1, body["totalEligibleUsersInEnterprise"])
    end

    test "returns [] if no members" do
      @business_team.add_member(@owner, caller_type: :business_team)
      @business_team.add_member(@user, caller_type: :business_team)

      as @owner
      get "/enterprises/#{@business.slug}/teams/#{@business_team.slug}/eligible_members", format: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal([], body["users"])
      assert_equal(0, body["totalEligibleUsersInEnterprise"])
    end
  end
end
