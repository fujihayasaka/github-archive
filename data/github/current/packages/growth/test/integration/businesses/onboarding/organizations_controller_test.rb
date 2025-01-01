# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessesOnboardingOrganizationsControllerHttpTest < GitHub::IntegrationTestCase
  skip_with_all_emus
  skip_enterprise

  fixtures do
    @business = create(:business)
    @owner = create(:user)
    @business.add_owner(@owner, actor: nil)
  end

  setup do
    GitHub.flipper[:disable_react_ssr].enable
    AzureEXP::Experiments.stubs(:enterprise_onboarding_org_create?).returns(true)
  end

  context "before_action" do
    test "render if enterprise owner is accessing the page" do
      as @owner
      get "/enterprises/#{@business}/onboarding/organizations/new"

      assert_response_success
    end

    test "render not found when user is not the enterprise owner" do
      user = create(:user)

      as user
      get "/enterprises/#{@business}/onboarding/organizations/new"

      assert_response_not_found
    end

    test "render not found when user is not signed in" do
      get "/enterprises/#{@business}/onboarding/organizations/new"

      assert_redirected_to_login
    end

    test "redirect to enterprise getting started page if user is not in the experiment enterprise_onboarding_org_create" do
      AzureEXP::Experiments.stubs(:enterprise_onboarding_org_create?).returns(false)

      as @owner
      get "/enterprises/#{@business}/onboarding/organizations/new"

      assert_redirected_to enterprise_getting_started_path(@business)
    end
  end
end
