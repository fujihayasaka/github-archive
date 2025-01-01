# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseTeamMembersControllerTest < GitHub::IntegrationTestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper
  include GitHub::ReactPayloadHelper
  include AuthenticationHelpers::SAML

  setup do
    if GitHub.single_business_environment?
      GitHub.stubs(:esm_enabled?).returns(true)
      setup_saml_auth_mode(with_scim: true)
      as @owner
      @enterprise_team_no_idp_3_members = create(:enterprise_team, business: @business, name: "no idp 3 members")
      @generic_members = []
      3.times do |i|
        user = create :user, business: @business, login: "user-#{i}", profile: create(:profile, name: "John Doe #{i}")
        @enterprise_team_no_idp_3_members.enterprise_team_memberships.create!(user: user)
        @generic_members << user
      end
    else
      as @owner, external_identities: @external_identity
      @enterprise_team_no_idp_3_members = create(:enterprise_team, business: @business, name: "no idp 3 members")
      @generic_members = []
      3.times do |i|
        user = create :emu, business: @business, login: "user-#{i}", profile: create(:profile, name: "John Doe #{i}")
        @enterprise_team_no_idp_3_members.enterprise_team_memberships.create!(user: user)
        @generic_members << user
      end
    end

    @enterprise_team_no_idp = create(:enterprise_team, business: @business, name: "no idp")
    perform_enqueued_jobs only: BusinessUserAccountUpdateAttributesJob
  end

  fixtures do
    if GitHub.single_business_environment?
      setup_saml_auth_mode(with_scim: true)
      @business = create :global_business
      @provider = create :business_saml_provider, business: @business
      @provider.update(scim_provisioning_state: "scim_provisioning_state_enabled")
      @owner = @business.owners.first
      @user = create :ghes_scim_user, business: @business
      @business.add_owner(@user, actor: @owner)
      @external_identity = @user.external_identities.first
      @unaffiliated = create(:user, login: "unaffiliated")
    else
      @owner = create :emu, :owner, name: "owner"
      @external_identity = @owner.external_identities.first
      @business = @owner.enterprise_managed_business
      @business.update(seats_plan_type: :basic)
      @unaffiliated = create(:user, login: "unaffiliated")
      @unaffiliated_user_account = create(:business_user_account, business: @business, user: @unaffiliated, business_roles_bitfield: 0)
    end

    perform_enqueued_jobs only: BusinessUserAccountUpdateAttributesJob
  end

  context "GET /enterprises/:slug/teams/:team_slug/members" do
    test "renders page" do
      get "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members"

      assert_response_success
    end

    test "returns 404" do
      get "/enterprises/not-a-business/teams/#{@enterprise_team_no_idp.slug}/members"

      assert_response_not_found
    end

    test "renders json results for direct members" do
      member = @enterprise_team_no_idp.enterprise_team_memberships.create!(user: @owner)
      get "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members", format: :json

      if GitHub.single_business_environment?
        expected_members = [{ "id" => @owner.id, "name" => @owner.name, "login" => @owner.display_login }]
      else
        business_account = @owner.business_user_account
        expected_members = [{ "id" => business_account.user_id, "name" => @owner.business_user_account.name, "login" => @owner.display_login }]
      end

      assert_response_success
      body = JSON.parse(response.body)
      assert_equal({
        "members" => expected_members,
        "total_members" => 1,
        "page_size" => 30,
      }, body)
    end

    test "renders json results for direct members as an ESM user" do
      member = @generic_members.first
      @enterprise_team_no_idp.enterprise_team_memberships.create!(user: member)
      EnterpriseTeamAssignment.create!(enterprise_team:  @enterprise_team_no_idp, assignment_type: "security_manager")
      SecurityProduct::EnterpriseSecurityManagerRole.grant!(@enterprise_team_no_idp)

      Organization.any_instance.expects(:visible_user_ids_for).never

      as member
      get "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members", format: :json

      if GitHub.single_business_environment?
        expected_members = [{ "id" => member.id, "name" => member.name, "login" => member.display_login }]
      else
        business_account = member.business_user_account
        expected_members = [{ "id" => business_account.user_id, "name" => member.business_user_account.name, "login" => member.display_login }]
      end

      assert_response_success
      body = JSON.parse(response.body)
      assert_equal({
        "members" => expected_members,
        "total_members" => 1,
        "page_size" => 30,
      }, body)
    end

    test "returns json results for IDP teams" do
      team = create(:enterprise_team, business: @business, name: "idp")
      external_group = create(:external_group, business: @business)
      EnterpriseTeamGroupMapping.create!(enterprise_team: team, external_group: external_group)
      ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: @external_identity)

      get "/enterprises/#{@business.slug}/teams/#{team.slug}/members", format: :json

      if GitHub.single_business_environment?
        expected_members = [{ "id" => @external_identity.user_id, "name" => @user.name, "login" => @user.display_login }]
      else
        business_account = @owner.business_user_account
        expected_members = [{ "id" => business_account.user_id, "name" => @owner.business_user_account.name, "login" => @owner.display_login }]
      end

      assert_response_success
      body = JSON.parse(response.body)
      assert_equal({
        "members" => expected_members,
        "total_members" => 1,
        "page_size" => 30,
      }, body)
    end

    context "pagination" do
      test "MEMBERS_PER_PAGE is 30" do
        assert_equal(30, EnterpriseTeamMembersController::MEMBERS_PER_PAGE)
      end

      test "paginates results" do
        EnterpriseTeamMembersController.stub_const(:MEMBERS_PER_PAGE, 2) do
          get "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp_3_members.slug}/members", format: :json

          assert_response_success
          body = JSON.parse(response.body)
          assert_equal(2, body["members"].count)
          assert_equal(3, body["total_members"])
        end
      end

      test "returns results on the proper page" do
        EnterpriseTeamMembersController.stub_const(:MEMBERS_PER_PAGE, 2) do
          get "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp_3_members.slug}/members?page=2", format: :json

          assert_response_success
          body = JSON.parse(response.body)
          assert_equal(1, body["members"].count)
          assert_equal(3, body["total_members"])
        end
      end

      test "no cap at page 100" do
        get "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp_3_members.slug}/members?page=101", format: :json

        assert_response_success
        body = JSON.parse(response.body)
        assert_equal(0, body["members"].count)
        assert_equal(3, body["total_members"])
      end
    end

    context "search" do
      test "can search by login" do
        member = @generic_members.first

        get "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp_3_members.slug}/members", format: :json, params: { query: member.display_login }

        assert_response_success
        body = JSON.parse(response.body)
        assert_equal(1, body["members"].count)
        assert_equal(member.display_login, body["members"].first["login"])
      end

      test "can search by partial login" do
        get "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp_3_members.slug}/members", format: :json, params: { query: "user" }

        assert_response_success
        body = JSON.parse(response.body)
        assert_equal(3, body["members"].count)
        assert_equal(@generic_members.map(&:display_login).sort, body["members"].map { |m| m["login"] }.sort)
      end

      test "can search by name" do
        name = "Some Name"
        member = @generic_members.first
        member.profile.update!(name: name)

        get "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp_3_members.slug}/members", format: :json, params: { query: name }

        assert_response_success
        body = JSON.parse(response.body)
        assert_equal(1, body["members"].count)
        if GitHub.single_business_environment?
          assert_equal(member.name, body["members"].first["name"]) # GHES user gets a name by default, same as display login
        else
          assert_equal(name, body["members"].first["name"])
        end
      end

      test "can search by partial name" do
        name = "Some Name"
        member = @generic_members.first
        member.profile.update!(name: name)

        get "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp_3_members.slug}/members", format: :json, params: { query: "Some N" }

        assert_response_success
        body = JSON.parse(response.body)
        assert_equal(1, body["members"].count)
        if GitHub.single_business_environment?
          assert_equal(member.name, body["members"].first["name"]) # GHES user gets a name by default, same as display login
        else
          assert_equal(name, body["members"].first["name"])
        end
      end
    end
  end

  context "POST /enterprises/:slug/teams/:team_slug/members" do
    test "returns 404 if team not found" do
      post "/enterprises/#{@business.slug}/teams/imaginary_team/members", params: {
        user_login: @owner.display_login,
      }

      assert_response_not_found
      response_json = JSON.parse(response.body)
      assert_equal "Team not found.", response_json["data"]["error"]
    end

    test "returns 400 if trying to add a member to an EMU managed team" do
      team = create(:enterprise_team, business: @business, name: "idp")
      external_group = create(:external_group, :with_members, business: @business, number_of_members: 1)
      EnterpriseTeamGroupMapping.create!(enterprise_team: team, external_group: external_group)

      post "/enterprises/#{@business.slug}/teams/#{team.slug}/members"

      assert_response_bad_request
      response_json = JSON.parse(response.body)
      assert_equal "Team does not allow direct memberships.", response_json["data"]["error"]
    end

    test "returns 400 if user not passed: api" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      post "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members"

      assert_response_bad_request
      response_json = JSON.parse(response.body)
      assert_equal "User login cannot be empty.", response_json["data"]["error"]
    end

    test "returns 404 if user not found" do
      post "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members", params: {
        user_login: "imaginary_user",
      }

      assert_response_not_found
      response_json = JSON.parse(response.body)
      assert_equal "User cannot be found in the enterprise.", response_json["data"]["error"]
    end

    test "returns 404 if user not in enterprise", skip_enterprise: true do
      owner2 = create :emu, :owner
      as @owner, external_identities: @external_identity

      post "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members", params: {
        user_login: owner2.display_login,
      }

      assert_response_not_found
      response_json = JSON.parse(response.body)
      assert_equal "User cannot be found in the enterprise.", response_json["data"]["error"]
    end

    test "endpoint adds a member" do
      post "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members", params: {
        user_login: @owner.display_login,
      }

      assert_response_success
      assert_equal @enterprise_team_no_idp.member_user_ids.count, 1
    end

    test "endpoint adds a unaffiliated member" do
      GitHub.flipper[:unaffiliated_user_accounts].enable
      post "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members", params: {
        user_login: @unaffiliated.display_login,
      }

      assert_response_success
      assert_equal @enterprise_team_no_idp.member_user_ids.count, 1
    end

    test "endpoint adds a unaffiliated member on a basic account" do
      @business.update(seats_plan_type: :basic)
      post "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members", params: {
        user_login: @unaffiliated.display_login,
      }

      assert_response_success
      assert_equal @enterprise_team_no_idp.member_user_ids.count, 1
    end

    test "The same user cannot be added twice" do
      post "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members", params: {
        user_login: @owner.display_login,
      }

      post "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members", params: {
        user_login: @owner.display_login,
      }

      assert_response_bad_request
      assert_equal @enterprise_team_no_idp.member_user_ids.count, 1
    end

    test "User must be an admin to add a user" do
      standard_user = if GitHub.single_business_environment?
        create :ghes_scim_user, business: @business
      else
        create :emu, business: @business
      end
      standard_user_external_identity = standard_user.external_identities.first
      as standard_user, external_identities: standard_user_external_identity
      post "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members", params: {
        user_login: @owner.display_login,
      }

      assert_response_not_found
      assert_equal @enterprise_team_no_idp.member_user_ids.count, 0
    end

    test "Added user must belong to the enterprise" do
      unrelated_owner = if GitHub.single_business_environment?
        create :ghes_scim_user, business: @business
      else
        create :emu, :owner
      end
      put "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members/#{unrelated_owner.display_login}"

      assert_response_not_found
      assert_equal @enterprise_team_no_idp.member_user_ids.count, 0
    end

    test "returns error when user is already part of the enterprise team" do
      user1 = if GitHub.single_business_environment?
        create :ghes_scim_user, business: @business, name: "test-user"
      else
        create :emu, business: @business, name: "test-user"
      end
      @business.add_owner(user1, actor: @owner) if GitHub.single_business_environment?
      EnterpriseTeamMembership.create!(enterprise_team: @enterprise_team_no_idp, user: user1)

      post "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members", params: {
        user_login: user1.display_login,
      }

      assert_response :bad_request
      response_json = JSON.parse(response.body)
      assert_equal "This user is already part of the enterprise team", response_json["data"]["error"]
    end
  end

  context "DELETE /enterprises/:slug/teams/:team_slug/members/:user_login" do
    test "returns 404 if called on non emu", skip_with_all_emus: true do
      non_emu_owner = create(:user)
      non_emu_business = create(:business, owners: [non_emu_owner])
      non_emu_enterprise_team = create(:enterprise_team, business: non_emu_business)
      GitHub.flipper[:enterprise_teams_direct_access].disable(non_emu_business)

      as non_emu_owner, external_identities: non_emu_owner.external_identities.first
      delete "/enterprises/#{non_emu_business.slug}/teams/#{non_emu_enterprise_team.slug}/members/#{non_emu_owner.display_login}"

      assert_response_not_found
    end unless GitHub.single_business_environment?

    test "returns 404 if called on standard (not basic) enterprise" do
      standard_owner = create :emu, :owner
      standard_emu = standard_owner.enterprise_managed_business
      standard_enterprise_team = create :enterprise_team, business: standard_emu
      GitHub.flipper[:enterprise_teams_direct_access].disable(standard_emu)

      as standard_owner, external_identities: standard_owner.external_identities.first
      delete "/enterprises/#{standard_emu.slug}/teams/#{standard_enterprise_team.slug}/members/#{standard_owner.display_login}"

      assert_response_not_found
    end unless GitHub.single_business_environment?

    test "returns 404 if team not found" do
      delete "/enterprises/#{@business.slug}/teams/imaginary_team/members/#{@owner.display_login}"

      assert_response_not_found
      response_json = JSON.parse(response.body)
      assert_equal "Team not found.", response_json["data"]["error"]
    end

    test "returns 400 if trying to remove a member from an EMU managed team" do
      team = create(:enterprise_team, business: @business, name: "idp")
      external_group = create(:external_group, :with_members, business: @business, number_of_members: 1)
      EnterpriseTeamGroupMapping.create!(enterprise_team: team, external_group: external_group)
      refute_nil team.member_user_ids.first
      user_to_remove = User.find(team.member_user_ids.first)
      refute_nil user_to_remove

      delete "/enterprises/#{@business.slug}/teams/#{team.slug}/members/#{user_to_remove.display_login}"

      assert_response_bad_request
      response_json = JSON.parse(response.body)
      assert_equal "Team does not allow direct memberships.", response_json["data"]["error"]
    end

    test "returns 404 if user not found" do
      delete "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members/imaginary_user"

      assert_response_not_found
      response_json = JSON.parse(response.body)
      assert_equal "User cannot be found in the enterprise.", response_json["data"]["error"]
    end

    test "returns 404 if user not in enterprise", skip_enterprise: true do
      owner2 = create :emu, :owner
      as @owner, external_identities: @external_identity

      delete "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members/#{owner2.display_login}"

      assert_response_not_found
      response_json = JSON.parse(response.body)
      assert_equal "User cannot be found in the enterprise.", response_json["data"]["error"]
    end

    test "returns ok if user is in enterprise team" do
      EnterpriseTeamMembership.create!(enterprise_team: @enterprise_team_no_idp, user: @owner)
      assert_equal @owner.id, @enterprise_team_no_idp.member_user_ids.first

      delete "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members/#{@owner.display_login}"

      assert_response_success
      response_json = JSON.parse(response.body)
      assert_empty response_json["data"]

      assert_nil @enterprise_team_no_idp.member_user_ids.first

      # gracefully allow repeat operation for the UI, see controller comment
      delete "/enterprises/#{@business.slug}/teams/#{@enterprise_team_no_idp.slug}/members/#{@owner.display_login}"

      assert_response_not_found
      response_json = JSON.parse(response.body)
      assert_equal "This user is not a member of the team.", response_json["data"]["error"]
    end
  end
end
