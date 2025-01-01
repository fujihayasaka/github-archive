# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationOnboarding::ApplicationControllerTest < GitHub::IntegrationTestCase

  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user, login: "myorg")
  end

  if GitHub.enterprise? || TestEnv.test_with_all_emus?
    context "404s when emu or enterprise server" do
      test "POST /orgs/:org_id/organization_onboarding/demo_repositories" do
        as @user
        post "/orgs/#{@org.id}/organization_onboarding/demo_repositories", params: { task: :open_pull_request }
        assert_response_not_found
      end
    end
  else
    test "redirects to login for anon" do
      @session.clear
      as nil

      url = "/orgs/myorg/organization_onboarding/demo_repositories"
      post url, params: { task: :open_pull_request }

      assert_redirected_to login_path(return_to: "http://github.com#{url}")
    end

    test "renders 404 when you are not the organization admin" do
      another_org = create(:organization, name: "Anotherorg", login: "anotherorg")
      another_org.add_member(@user)

      as @user

      post "/orgs/anotherorg/organization_onboarding/demo_repositories", params: { task: :open_pull_request }

      assert_response 404
    end
  end
end
