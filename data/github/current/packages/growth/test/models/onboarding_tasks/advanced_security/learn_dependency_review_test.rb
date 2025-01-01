# typed: true
# frozen_string_literal: true

require "test_helper"

class OnboardingTasks::AdvancedSecurity::LearnDependencyReviewTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @owner = create(:user)
    @org = create(:organization, login: "ACME", admin: @owner)
  end

  setup do
    @verify_stub = stub(completed_onboarding_tasks: [], verify: true)
  end

  context "#complete_task" do
    test "saves the completed task on the organization" do
      OnboardingTasks::AdvancedSecurity::LearnDependencyReview.new(taskable: @org, user: @owner).complete

      assert_equal [:learn_dependency_review], @org.reload.completed_onboarding_tasks
    end

    test "publishes a hydro event" do
      OnboardingTasks::AdvancedSecurity::LearnDependencyReview.new(taskable: @org, user: @owner).complete

      assert_hydro_published({
        user: Hydro::EntitySerializer.user(@owner),
        type: "advanced_security",
        task: "learn_dependency_review",
        completed_tasks: ["learn_dependency_review"],
        remaining_tasks: [],
        taskable_type: "Organization",
        taskable_id: @org.id,
      }, schema: "github.v1.OnboardingTaskCompleted")
    end

    test "has a title" do
      assert_equal(
        "Learn about dependency review",
        OnboardingTasks::AdvancedSecurity::LearnDependencyReview.new(taskable: @org, user: @owner).title
      )
    end

    test "has a task link" do
      assert_equal(
        "#{GitHub.help_url}/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/reviewing-dependency-changes-in-a-pull-request#reviewing-dependencies-in-a-pull-request",
        OnboardingTasks::AdvancedSecurity::LearnDependencyReview.new(taskable: @org, user: @owner).task_link
      )
    end
  end
end
