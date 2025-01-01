# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationOnboarding::ShowTasksControllerTest < GitHub::IntegrationTestCase

  fixtures do
    @user = create(:user)
    @organization = create(:organization, admin: @user, login: "myorg")
    make_trusted_oauth_apps_owner
    create(:launch_integration)
  end

  if GitHub.enterprise? || TestEnv.test_with_all_emus?
    context "404s when emu or enterprise server" do
      test "PATCH /orgs/myorg/organization_onboarding/show_tasks" do
        as @user
        request_env["HTTP_REFERER"] = "/myorg"
        patch "/orgs/myorg/organization_onboarding/show_tasks",  params: { show_onboarding_tasks: true }

        assert_response_not_found
      end
    end
  else
    context "POST #update" do
      test "redirects to login for anon" do
        @session.clear
        as nil

        patch "/orgs/myorg/organization_onboarding/show_tasks"

        assert_redirected_to login_path(return_to: "http://github.com/orgs/myorg/organization_onboarding/show_tasks")
      end

      test "renders 404 when you are not the organization admin" do
        another_org = create(:organization, name: "Anotherorg", login: "anotherorg")
        another_org.add_member(@user)

        as @user

        patch "/orgs/anotherorg/organization_onboarding/show_tasks"

        assert_response 404
      end

      test "sets show_onboarding_tasks field to true" do
        as @user
        request_env["HTTP_REFERER"] = "/myorg"
        patch "/orgs/myorg/organization_onboarding/show_tasks",  params: { show_onboarding_tasks: true }

        @organization.reload
        assert @organization.show_onboarding_tasks
        assert_response :redirect
        assert_redirected_to "/myorg"
      end

      test "sets show_onboarding_tasks field to false" do
        as @user
        @organization.update(show_onboarding_tasks: true)
        patch "/orgs/myorg/organization_onboarding/show_tasks", params: { show_onboarding_tasks: false }

        @organization.reload
        refute @organization.show_onboarding_tasks
        assert_response :redirect
        assert_redirected_to "http://github.com"
      end
    end
  end
end
