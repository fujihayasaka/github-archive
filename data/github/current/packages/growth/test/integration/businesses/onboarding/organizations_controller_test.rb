# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessesOnboardingOrganizationsControllerHttpTest < GitHub::IntegrationTestCase
  include FineGrainedPermissionsTestHelper
  skip_with_all_emus
  skip_enterprise

  fixtures do
    @business = create(:business)
    @owner = create(:user)
    @business.add_owner(@owner, actor: nil)
    @member_with_organization_create_role = create :user, :verified
    @member_with_read_enterprise_custom_enterprise_role = create :user, :verified
  end

  setup do
    enable_feature_flag(:disable_react_ssr)
  end

  context "before_action" do
    test "render if enterprise owner is accessing the page" do
      as @owner
      get "/enterprises/#{@business}/onboarding/organizations/new"

      assert_response_success
    end

    test "does not render subnav" do
      as @owner
      get "/enterprises/#{@business}/onboarding/organizations/new"

      assert_response_success
      refute_test_selector "local-nav"
    end

    test "render not found when user is not the enterprise owner" do
      user = create(:user)

      as user
      get "/enterprises/#{@business}/onboarding/organizations/new"

      assert_response_not_found
    end

    test "render not found when user has incorrect permissions" do
      enable_feature_flag(:custom_enterprise_role_feature, @business)
      grant_custom_enterprise_role(user: @member_with_read_enterprise_custom_enterprise_role, target: @business, fgps: [:read_enterprise_custom_enterprise_role])
      as @member_with_read_enterprise_custom_enterprise_role
      get "/enterprises/#{@business}/onboarding/organizations/new"

      assert_response_not_found
    end

    test "renders if user has correct permissions" do
      enable_feature_flag(:custom_enterprise_role_feature, @business)
      grant_custom_enterprise_role(user: @member_with_organization_create_role, target: @business, fgps: [:create_enterprise_organizations])
      as @member_with_organization_create_role
      get "/enterprises/#{@business}/onboarding/organizations/new"

      assert_response_success
    end

    test "render not found when user is not signed in" do
      get "/enterprises/#{@business}/onboarding/organizations/new"

      assert_redirected_to_login
    end
  end
end
