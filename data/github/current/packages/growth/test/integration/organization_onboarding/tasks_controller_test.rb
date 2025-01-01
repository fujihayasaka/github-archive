# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationOnboarding::TasksControllerTest < GitHub::IntegrationTestCase

  fixtures do
    @owner = create(:user)
    @organization = create(:organization, admin: @owner, login: "acme")
  end

  if GitHub.enterprise? || TestEnv.test_with_all_emus?
    context "404s when emu or enterprise server" do
      test "PATCH /orgs/acme/organization_onboarding/tasks" do
        as @owner
        patch "/orgs/acme/organization_onboarding/show_tasks",  params: { task: "learn_dependency_review" }, xhr: true

        assert_response_not_found
      end
    end
  else
    context "POST #update" do
      context "xhr" do
        test "not authorized for anon" do
          as nil

          patch "/orgs/acme/organization_onboarding/tasks",  params: { task: "learn_dependency_review" }, xhr: true

          assert_response_unauthorized
        end

        test "renders 404 when you are not the organization admin" do
          another_org = create(:organization, name: "Anotherorg", login: "anotherorg")
          another_org.add_member(@owner)

          as @owner

          patch "/orgs/anotherorg/organization_onboarding/tasks",  params: { task: "learn_dependency_review" }, xhr: true

          assert_response_not_found
        end

        test "sets show_onboarding_tasks field to true" do
          refute OnboardingTasks::AdvancedSecurity::LearnDependencyReview.new(taskable: @organization, user: @owner).completed?
          as @owner
          patch "/orgs/acme/organization_onboarding/tasks",  params: { task: "learn_dependency_review" }, xhr: true

          @organization.reload
          assert OnboardingTasks::AdvancedSecurity::LearnDependencyReview.new(taskable: @organization, user: @owner).completed?
          assert_response_success
          json = JSON.parse(response.body)
          assert_equal({ "task_completed" => true }, json)
        end

        test "sets customize_permissions field to true" do
          refute OnboardingTasks::Organizations::CustomizePermission.new(taskable: @organization, user: @owner).completed?
          as @owner
          patch "/orgs/acme/organization_onboarding/tasks",  params: { task: "customize_permission" }, xhr: true

          @organization.reload
          assert OnboardingTasks::Organizations::CustomizePermission.new(taskable: @organization, user: @owner).completed?
          assert_response_success
          json = JSON.parse(response.body)
          assert_equal({ "task_completed" => true }, json)
        end

        test "returns error with unknown task" do
          as @owner
          patch "/orgs/acme/organization_onboarding/tasks",  params: { task: "foo" }, xhr: true
          json = JSON.parse(response.body)
          assert_equal({ "error" => "Invalid task: foo" }, json)
          assert_response 422
        end

        test "returns error when update fails" do
          Organization.any_instance.stubs(:update).returns(false)
          refute OnboardingTasks::AdvancedSecurity::LearnDependencyReview.new(taskable: @organization, user: @owner).completed?
          as @owner
          patch "/orgs/acme/organization_onboarding/tasks",  params: { task: "learn_dependency_review" }, xhr: true

          @organization.reload
          refute OnboardingTasks::AdvancedSecurity::LearnDependencyReview.new(taskable: @organization, user: @owner).completed?
          assert_response 500
          json = JSON.parse(response.body)
          assert_equal({ "error" => "Failed to complete task: learn_dependency_review" }, json)
        end
      end
    end
    context "html" do
      test "anon redirects to login" do
        as nil

        patch "/orgs/acme/organization_onboarding/tasks",  params: { task: "learn_dependency_review" }
        assert_redirected_to login_path(return_to: "http://github.com/orgs/acme/organization_onboarding/tasks")
      end

      test "renders 404 when you are not the organization admin" do
        another_org = create(:organization, name: "Anotherorg", login: "anotherorg")
        another_org.add_member(@owner)

        as @owner

        patch "/orgs/anotherorg/organization_onboarding/tasks",  params: { task: "learn_dependency_review" }

        assert_response_not_found
      end

      test "sets show_onboarding_tasks field to true" do
        refute OnboardingTasks::AdvancedSecurity::LearnDependencyReview.new(taskable: @organization, user: @owner).completed?
        as @owner
        patch "/orgs/acme/organization_onboarding/tasks",  params: {
          task: "learn_dependency_review",
          return_to: "/orgs/acme/organization_onboarding/advanced_security"
        }

        @organization.reload
        assert OnboardingTasks::AdvancedSecurity::LearnDependencyReview.new(taskable: @organization, user: @owner).completed?

        assert_redirected_to "/orgs/acme/organization_onboarding/advanced_security"
        assert_equal "Completed task", flash[:success]
      end

      test "returns error with unknown task" do
        as @owner
        patch "/orgs/acme/organization_onboarding/tasks", params: {
          task: "foo",
          return_to: "/orgs/acme/organization_onboarding/advanced_security"
        }
        assert_redirected_to "/orgs/acme/organization_onboarding/advanced_security"
        assert_equal "Unknown task", flash[:error]
      end

      test "returns error when update fails" do
        Organization.any_instance.stubs(:update).returns(false)
        refute OnboardingTasks::AdvancedSecurity::LearnDependencyReview.new(taskable: @organization, user: @owner).completed?
        as @owner
        patch "/orgs/acme/organization_onboarding/tasks", params: {
          task: "learn_dependency_review",
          return_to: "/orgs/acme/organization_onboarding/advanced_security"
        }
        @organization.reload
        refute OnboardingTasks::AdvancedSecurity::LearnDependencyReview.new(taskable: @organization, user: @owner).completed?
        assert_redirected_to "/orgs/acme/organization_onboarding/advanced_security"
        assert_equal "Failed to complete task", flash[:error]
      end
    end
  end
end
