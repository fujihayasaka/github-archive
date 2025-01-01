# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseTeamMemberSuggestionsControllerTest < GitHub::IntegrationTestCase
  extend T::Helpers
  include BusinessTestHelpers

  fixtures do
    @owner = create(:user, login: "prefixThisIsALongLoginSuffix")
    @owner.profile_name = nil
    @owner.save!
    @owner2 = create(:user, login: "athisIsALongLoginb")
    @owner2.profile_name = "Owner 2"
    @owner2.save!
    @unaffiliated = create(:user, login: "unaffiliated")
    @business = create(:business, owners: [@owner, @owner2])
    @member = create :user, business: @business
    @unaffiliated_user_account = create(:business_user_account, business: @business, user: @unaffiliated, business_roles_bitfield: 0)
  end

  context "GET /enterprises/:slug/enterprise_team_member_suggestions" do
    test_business_access do
      T.unsafe(self).get "/enterprises/#{@business.slug}/enterprise_team_member_suggestions", format: :json
    end

    test "returns no enterprise members when no query parameter" do
      as @owner
      get "/enterprises/#{@business.slug}/enterprise_team_member_suggestions", format: :json

      assert_response :success
      body = JSON.parse(response.body)
      refute_nil body["enterprise_members"]
      assert_equal(0, body["enterprise_members"].count)
    end

    test "can search by full login" do
      as @owner
      get "/enterprises/#{@business.slug}/enterprise_team_member_suggestions", format: :json, params: { query: "prefixThisIsALongLoginSuffix" }

      assert_response_success
      body = JSON.parse(response.body)
      refute_nil body["enterprise_members"]
      assert_equal(1, body["enterprise_members"].count)

      assert_equal @owner.id, body["enterprise_members"].first["id"]
      if GitHub.single_business_environment?
        assert_equal @owner.name, body["enterprise_members"].first["name"] # GHES user gets a name by default, same as display login
      else
        assert_nil body["enterprise_members"].first["name"]
      end
      assert_equal @owner.display_login, body["enterprise_members"].first["login"]
    end

    test "can search by login substring" do
      as @owner
      get "/enterprises/#{@business.slug}/enterprise_team_member_suggestions", format: :json, params: { query: "thisIsALongLogin" }

      assert_response_success
      body = JSON.parse(response.body)
      refute_nil body["enterprise_members"]
      assert_equal(2, body["enterprise_members"].count)

      assert_equal @owner2.id, body["enterprise_members"].first["id"]
      if GitHub.single_business_environment?
        assert_equal @owner2.name, body["enterprise_members"].first["name"] # GHES user gets a name by default, same as display login
      else
        assert_equal "Owner 2", body["enterprise_members"].first["name"]
      end
      assert_equal @owner2.display_login, body["enterprise_members"].first["login"]

      assert_equal @owner.id, body["enterprise_members"].last["id"]
      if GitHub.single_business_environment?
        assert_equal @owner.name, body["enterprise_members"].last["name"] # GHES user gets a name by default, same as display login
      else
        assert_nil body["enterprise_members"].last["name"]
      end
      assert_equal @owner.display_login, body["enterprise_members"].last["login"]
    end
  end

  test "can search by full name" do
    as @owner
    get "/enterprises/#{@business.slug}/enterprise_team_member_suggestions", format: :json, params: { query: "Owner 2" }

    assert_response_success
    body = JSON.parse(response.body)
    refute_nil body["enterprise_members"]
    assert_equal(1, body["enterprise_members"].count)

    assert_equal @owner2.id, body["enterprise_members"].first["id"]
    if GitHub.single_business_environment?
      assert_equal @owner2.name, body["enterprise_members"].first["name"] # GHES user gets a name by default, same as display login
    else
      assert_equal "Owner 2", body["enterprise_members"].first["name"]
    end
    assert_equal @owner2.display_login, body["enterprise_members"].first["login"]
  end

  test "can search by name substring" do
    as @owner
    get "/enterprises/#{@business.slug}/enterprise_team_member_suggestions", format: :json, params: { query: "wner" }

    assert_response_success
    body = JSON.parse(response.body)
    refute_nil body["enterprise_members"]
    assert_equal(1, body["enterprise_members"].count)

    assert_equal @owner2.id, body["enterprise_members"].first["id"]
    if GitHub.single_business_environment?
      assert_equal @owner2.name, body["enterprise_members"].first["name"] # GHES user gets a name by default, same as display login
    else
      assert_equal "Owner 2", body["enterprise_members"].first["name"]
    end
    assert_equal @owner2.display_login, body["enterprise_members"].first["login"]
  end

  test "includes unaffiliated users in results" do
    GitHub.flipper[:unaffiliated_user_accounts].enable
    as @owner
    get "/enterprises/#{@business.slug}/enterprise_team_member_suggestions", format: :json, params: { query: "unaffiliated" }

    assert_response_success
    body = JSON.parse(response.body)
    refute_nil body["enterprise_members"]
    assert_equal(1, body["enterprise_members"].count)

    assert_equal @unaffiliated.id, body["enterprise_members"].first["id"]
    if GitHub.single_business_environment?
      assert_equal @unaffiliated.name, body["enterprise_members"].first["name"] # GHES user gets a name by default, same as display login
    else
      assert_nil body["enterprise_members"].first["name"]
    end
    assert_equal @unaffiliated.display_login, body["enterprise_members"].first["login"]
  end if !TestEnv.test_with_all_emus? && !TestEnv.test_in_multitenancy_mode?

  test "includes unaffiliated users in results for basic enterprise" do
    @business.update(seats_plan_type: :basic)
    as @owner
    get "/enterprises/#{@business.slug}/enterprise_team_member_suggestions", format: :json, params: { query: "unaffiliated" }

    assert_response_success
    body = JSON.parse(response.body)
    refute_nil body["enterprise_members"]
    assert_equal(1, body["enterprise_members"].count)

    assert_equal @unaffiliated.id, body["enterprise_members"].first["id"]
    if GitHub.single_business_environment?
      assert_equal @unaffiliated.name, body["enterprise_members"].first["name"] # GHES user gets a name by default, same as display login
    else
      assert_nil body["enterprise_members"].first["name"]
    end
    assert_equal @unaffiliated.display_login, body["enterprise_members"].first["login"]
  end if !TestEnv.test_with_all_emus? && !TestEnv.test_in_multitenancy_mode?
end
