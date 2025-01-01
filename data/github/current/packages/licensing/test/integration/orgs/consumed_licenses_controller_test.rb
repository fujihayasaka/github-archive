# typed: true
# frozen_string_literal: true

require "test_helper"

class OrgsConsumedLicensesControllerHttpTest < GitHub::IntegrationTestCase
  fixtures do
    @admin = create(:user)
    @billing_manager = create(:user)
    @member = create(:user)
    @invited_email = "invited@example.com"

    @organization = create(:organization, plan: "business", seats: 5, admins: [@admin])

    @organization.add_member(@member)
    @organization.billing.add_manager(@billing_manager, actor: @admin)
    @organization.invite(email: @invited_email, inviter: @admin)
  end

  context "GET /organizations/:organization_id/consumed_licenses" do
    if GitHub.billing_enabled?
      test "404s when organization not found" do
        as @admin

        get "/organizations/not-a-real-organization-login/consumed_licenses"

        assert_response :not_found
      end

      test "404s when the current user is not a billing admin of the organization" do
        as @member

        get "/organizations/#{@organization.display_login}/consumed_licenses"

        assert_response :not_found
      end

      test "404s when the organization is not on a per-seat plan", skip_with_all_emus: true do
        @organization.update!(plan: "free")
        as @admin

        get "/organizations/#{@organization.display_login}/consumed_licenses"

        assert_response :not_found
      end

      test "renders a list of users/emails consuming licenses for billing managers when on a per-seat plan" do
        as @billing_manager

        get "/organizations/#{@organization.display_login}/consumed_licenses"

        assert_response :success

        assert_match(/#{@invited_email}/, response.body)
        assert_match(/#{@member.display_login}/, response.body)
      end

      # https://github.com/github/sponsors/issues/3846
      test "404s when a different org is specified in a query parameter than in the path and viewer lacks access" do
        rando = create(:user)
        rando_org = create(:organization, admin: rando)

        as rando
        get "/organizations/#{rando_org.display_login}/consumed_licenses", params: { org: @organization.login }

        assert_response :not_found
      end

      test "renders a list of users/emails consuming licenses for admins when on a per-seat plan" do
        as @admin

        get "/organizations/#{@organization.display_login}/consumed_licenses"

        assert_response :success

        assert_match(/#{@invited_email}/, response.body)
        assert_match(/#{@member.display_login}/, response.body)
      end

      test "allows pagination to go over 100" do
        as @admin

        get "/organizations/#{@organization.display_login}/consumed_licenses?page=101"

        assert_response :success
      end
    else
      test "404s when billing is disabled" do
        as @admin

        get "/organizations/#{@organization.display_login}/consumed_licenses"

        assert_response :not_found
      end
    end
  end
end
