# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationOnboarding::DemoRepositoriesControllerTest < GitHub::IntegrationTestCase

  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user, login: "myorg")
    make_trusted_oauth_apps_owner
    create(:launch_integration)
  end

  setup do
    Failbot.reports.clear
  end

  if GitHub.enterprise? || TestEnv.test_with_all_emus?
    context "404s when emu or enterprise server" do
      test "POST /orgs/myorg/organization_onboarding/demo_repositories" do
        as @user

        assert_difference -> { Repository.count }, 0 do
          post "/orgs/myorg/organization_onboarding/demo_repositories", params: { task: :open_pull_request }
        end

        assert_response_not_found
      end
    end
  else
    context "POST #create" do
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

      test "creates a demo repository and redirects to the task page" do
        as @user

        assert_difference -> { Repository.count }, 1 do
          post "/orgs/myorg/organization_onboarding/demo_repositories", params: { task: :open_pull_request }
        end

        assert_response :redirect
        assert_redirected_to "/myorg/demo-repository/compare/main...add-badges-to-readme?show_onboarding_guide_tip=true"
        assert_dogstats_increment(1, "organization.created_demo_repo", tags: ["status:success"])
      end

      test "if demo repo fails to create, redirects to onboarding and displays a flash error" do
        as @user
        OrganizationOnboard::DemoRepository.any_instance.stubs(:setup).raises(OrganizationOnboard::DemoRepository::FailedRepositoryCreationError.new("oops"))
        assert_difference -> { Repository.count }, 0 do
          post "/orgs/myorg/organization_onboarding/demo_repositories", params: { task: :open_pull_request }
        end

        assert_equal "The demo repository for your task could not be created. Please try again later.", flash[:error]
        assert_redirected_to "/myorg"
        assert_dogstats_increment(1, "organization.created_demo_repo", tags: ["status:error"])

        assert_equal 1, Failbot.reports.size
        report = Failbot.reports.last
        assert_equal "oops", Failbot.exception_message_from_hash(report)
      end

      test "does not create a demo repository if demo repo already exists" do
        as @user
        OrganizationOnboard::DemoRepository.new(organization: @org).setup(@user)

        assert_no_difference -> { Repository.count } do
          post "/orgs/myorg/organization_onboarding/demo_repositories", params: { task: :open_pull_request }
        end

        assert_response :redirect
        assert_redirected_to "/myorg/demo-repository/compare/main...add-badges-to-readme?show_onboarding_guide_tip=true"
      end
    end
  end
end
