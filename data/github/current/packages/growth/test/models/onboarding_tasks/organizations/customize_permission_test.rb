# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Organizations
    class CustomizePermissionTest < GitHub::TestCase
      fixtures do
        @owner = create(:user)
        @org = create(:organization, login: "ACME", admin: @owner)
      end

      context  "verify_task" do
        test "returns false if org if it is not included in completed_onboarding_tasks" do
          @org.update(completed_onboarding_tasks: [:invite_member])

          refute OnboardingTasks::Organizations::CustomizePermission.new(taskable: @org, user: @owner).verify_task
        end

        test "returns true if org if it is included in completed_onboarding_tasks" do
          @org.update(completed_onboarding_tasks: [OnboardingTasks::Organizations::CustomizePermission::TASK_KEY])

          assert OnboardingTasks::Organizations::CustomizePermission.new(taskable: @org, user: @owner).verify_task
        end

        test "returns true if task was completed" do
          task = OnboardingTasks::Organizations::CustomizePermission.new(taskable: @org, user: @owner)
          task.complete

          assert task.verify_task
        end

        test "returns true if org sets members permissions to write" do
          @org.update_default_repository_permission(:write, actor: @owner)

          assert OnboardingTasks::Organizations::CustomizePermission.new(taskable: @org, user: @owner).verify_task
        end

        test "returns true if org sets members permissions to admin" do
          @org.update_default_repository_permission(:admin, actor: @owner)

          assert OnboardingTasks::Organizations::CustomizePermission.new(taskable: @org, user: @owner).verify_task
        end

        test "returns false with database error" do
          @org.stubs(:completed_onboarding_tasks).raises(ActiveRecord::ConnectionTimeoutError)

          refute OnboardingTasks::Organizations::CustomizePermission.new(taskable: @org, user: @owner).verify_task
        end
      end

      test "has correct task_link" do
        members_privileges_path = "/organizations/#{@org.name}/settings/member_privileges?enable_tip=true"

        assert_equal members_privileges_path, OnboardingTasks::Organizations::CustomizePermission.new(taskable: @org, user: @owner).task_link
      end

      test "has correct title" do
        assert_equal "Customize members' permissions", OnboardingTasks::Organizations::CustomizePermission.new(taskable: @org, user: @owner).title
      end

      test "has correct icon path" do
        assert_equal "modules/dashboard/suggestions/permissions.svg", OnboardingTasks::Organizations::CustomizePermission.new(taskable: @org, user: @owner).icon_path
      end
    end
  end
end
