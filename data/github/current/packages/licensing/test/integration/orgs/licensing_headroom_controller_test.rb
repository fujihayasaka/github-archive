# typed: true
# frozen_string_literal: true

require "test_helper"

class Orgs::LicensingHeadroomControllerTest < GitHub::IntegrationTestCase
  include AuthenticationHelpers

  fixtures do
    @owner = create(:user)
    @admin = create(:user)
    @member = create(:user)

    @organization = create(:organization, admins: [@admin, @owner])
    @business = create :business, owners: [@owner], organizations: [@organization]
    @organization.add_member(@member)
  end

  test "returns licensing headroom information for organization admins" do
    as @admin

    get "/orgs/#{@organization.display_login}/licensing_headroom"

    assert_response :ok
  end

  test "returns 404 for non-admins" do
    as @member

    get "/orgs/#{@organization.display_login}/licensing_headroom"

    assert_response :not_found
  end

  test "does not show data to anonymous users" do
    get "/orgs/#{@organization.display_login}/licensing_headroom"

    assert_redirected_to_login
  end

  test "does not show `buy more` link for non enterprise admins" do
    as @admin

    get "/orgs/#{@organization.display_login}/licensing_headroom"

    refute_match "Buy more", response.body
  end

  test "shows `buy more` link when enterprise admin + org owner" do
    as @owner

    get "/orgs/#{@organization.display_login}/licensing_headroom"

    assert_match "Buy more", response.body
  end
end
