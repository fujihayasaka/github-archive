# typed: true
# frozen_string_literal: true
require "test_helper"

class Orgs::InvitationsLicensingDetailsControllerTest < GitHub::IntegrationTestCase
  include AuthenticationHelpers

  fixtures do
    @admin = create(:user)
    @org_admin = create(:user)
    @member = create(:user)

    @organization = create(:organization, admins: [@admin])
    @organization.add_member(@member)

    @business = create(:business, owners: [@admin])
    @business_org = create(:organization, business: @business, admins: [@admin, @org_admin])
  end

  test "renders licensing details for organization admins" do
    as @admin

    get "/orgs/#{@organization.display_login}/invitations/licensing_details"

    assert_response :ok
  end

  test "returns 404 for non-admins" do
    as @member

    get "/orgs/#{@organization.display_login}/invitations/licensing_details"

    assert_response :not_found
  end

  test "does not show data to anonymous users" do
    get "/orgs/#{@organization.display_login}/invitations/licensing_details"

    assert_redirected_to_login
  end

  test "shows only available seats message to orgs", skip_with_all_emus: true do
    as @admin

    get "/orgs/#{@organization.display_login}/invitations/licensing_details"

    assert_response :ok
    assert_select "[data-test-selector=license-details-available-seats]"
    refute_select "[data-test-selector=license-details-business-message]"
  end

  test "shows available seats and business messages to businesses", skip_with_all_emus: true do
    as @admin

    get "/orgs/#{@business_org.display_login}/invitations/licensing_details"

    assert_response :ok
    assert_select "[data-test-selector=license-details-available-seats]"
    assert_select "[data-test-selector=license-details-business-message]"
  end

  test "hides `buy more` licensing button for non-business owners", skip_with_all_emus: true do
    as @org_admin

    get "/orgs/#{@business_org.display_login}/invitations/licensing_details"

    assert_response :ok
    assert_select "[data-test-selector=license-details-available-seats]"
    assert_select "[data-test-selector=license-details-business-message]"
    refute_match "or buy more.", response.body
  end

  unless GitHub.single_business_environment?
    test "does not show business messages to EMU organization" do
      Organization.any_instance.stubs(:enterprise_managed_user_enabled?).returns(true)
      as @admin

      get "/orgs/#{@business_org.display_login}/invitations/licensing_details"

      assert_response :ok
      assert_empty response.body
    end

    test "shows license warnings when EMU has no seats available" do
      Organization.any_instance.stubs(:enterprise_managed_user_enabled?).returns(true)
      Business.any_instance.stubs(:seats).returns(0)

      as @admin

      get "/orgs/#{@business_org.display_login}/invitations/licensing_details"

      assert_response :ok
      refute_select "[data-test-selector=license-details-available-seats]"
      refute_select "[data-test-selector=license-details-business-message]"
      assert_select "[data-test-selector=license-details-emu-license-warning]"
    end
  end
end
