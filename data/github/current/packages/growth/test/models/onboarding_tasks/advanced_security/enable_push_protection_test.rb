# typed: true
# frozen_string_literal: true

require "test_helper"

class OnboardingTasks::AdvancedSecurity::EnablePushProtectionTest < GitHub::TestCase
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
      OnboardingTasks::AdvancedSecurity::EnablePushProtection.new(taskable: @org, user: @owner).complete

      assert_equal [:enable_push_protection], @org.reload.completed_onboarding_tasks
    end

    test "publishes a hydro event" do
      OnboardingTasks::AdvancedSecurity::EnablePushProtection.new(taskable: @org, user: @owner).complete

      assert_hydro_published({
        user: Hydro::EntitySerializer.user(@owner),
        type: "advanced_security",
        task: "enable_push_protection",
        completed_tasks: ["enable_push_protection"],
        remaining_tasks: [],
        taskable_type: "Organization",
        taskable_id: @org.id,
      }, schema: "github.v1.OnboardingTaskCompleted")
    end

    test "has a title" do
      assert_equal "Enable push protection", OnboardingTasks::AdvancedSecurity::EnablePushProtection.new(taskable: @org, user: @owner).title
    end

    test "has a task link" do
      assert_equal "/organizations/ACME/settings/security_analysis?tip=push_protection", OnboardingTasks::AdvancedSecurity::EnablePushProtection.new(taskable: @org, user: @owner).task_link
    end
  end
end
