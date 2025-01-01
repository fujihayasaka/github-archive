# typed: strict
# frozen_string_literal: true

require "test_helper"

class BusinessesLicenseCountsControllerHttpTest < GitHub::IntegrationTestCase
  include BusinessTestHelpers

  fixtures do
    @rando = T.let(create(:user), T.nilable(User))
    @user = T.let(create(:user), T.nilable(User))
    @member = T.let(create(:user), T.nilable(User))
    @owner = T.let(create(:user), T.nilable(User))
    @collaborator = T.let(create(:user), T.nilable(User))
    @collaborator2 = T.let(create(:user), T.nilable(User))
    T.must(@collaborator2).two_factor_credential = create :two_factor_credential

    @org = T.let(create(:organization, admins: [@member]), T.nilable(Organization))
    @repository = T.let(create(:repository, :minimal, owner: @org), T.nilable(Repository))
    T.must(@repository).add_member @collaborator
    T.must(@repository).add_member @collaborator2

    @business = T.let(create(:business, owners: [@owner], organizations: [@org]), T.nilable(Business))
  end

  context "GET /enterprises/:slug/license_counts/:metric" do
    test_business_access do
      get "/enterprises/#{@business}/license_counts/total_licenses_used"
    end

    test "responds with a 404 if user is not an owner" do
      as @user
      get "/enterprises/#{@business}/license_counts/total_licenses_used"
      assert_response :not_found
    end

    test "responds with a 404 if the business doesn't exist" do
      as @owner
      get "/enterprises/non-existent/license_counts/total_licenses_used"
      assert_response :not_found
    end

    test "responds with a 404 for a non-existent metric" do
      as @owner
      get "/enterprises/#{@business}/license_counts/coffee_cups_consumed"
      assert_response :not_found
    end

    test "succeeds if the business exists and user is an owner" do
      as @owner
      get "/enterprises/#{@business}/license_counts/total_licenses_used"
      assert_response :success
    end

    test "responds for total_licenses_used" do
      as @owner
      get "/enterprises/#{@business}/license_counts/total_licenses_used"
      assert_test_selector "license-count-number", text: T.must(@business).total_consumed_licenses.to_s
    end

    test "responds for enterprise_licenses" do
      as @owner
      get "/enterprises/#{@business}/license_counts/enterprise_licenses"
      assert_test_selector "license-count-number", text: T.must(@business).consumed_enterprise_licenses.to_s
    end

    unless GitHub.single_business_environment?
      test "responds for standalone_copilot_licenses", skip_with_all_emus: true do
        business = create :business, seats_plan_type: :basic
        ent_team = create :copilot_enterprise_team, team_name: "team1", member_count: 0, supplied_business: business
        assignment = create(:copilot_seat_assignment, :enterprise_team, team_name: "team1", member_count: 0, supplied_business: business, business: business, supplied_enterprise_team: ent_team)
        unaffiliated = create :user
        admin = business.owners.first
        create :business_user_account, business: business, user: unaffiliated, business_roles_bitfield: 0
        ent_team.enterprise_team_group_mappings.destroy_all
        ent_team.bulk_add_members(users: [unaffiliated])
        EnterpriseTeamAssignment.create!(enterprise_team: ent_team, assignment_type: "copilot")
        Copilot::Business.new(business).assign([ent_team], admin)

        as admin
        get "/enterprises/#{business}/license_counts/standalone_copilot_licenses"
        assert_test_selector "license-count-number", text: "1"
      end
    end

    test "responds for visual_studio_subscriptions" do
      T.must(@business).enterprise_agreements.create \
        agreement_id: "test",
        seats: 72,
        category: :visual_studio_bundle,
        status: :active
      as @owner
      get "/enterprises/#{@business}/license_counts/visual_studio_subscriptions"
      assert_test_selector "license-count-total", text: T.must(@business).purchased_volume_licenses_with_overages.to_s
    end

    # skip_with_all_emus - no organization invitations for EMUs
    test "responds for pending_invitation_licenses_used", skip_with_all_emus: true do
      email_invitation = create :organization_invitation, :email, role: :admin, organization: @org
      as @owner
      get "/enterprises/#{@business}/license_counts/pending_invitation_licenses_used"
      assert_test_selector "license-count-number", text: T.must(@business).consumed_pending_invitation_licenses.to_s
    end
  end
end
