# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Organizations
    class SomeTask < OnboardingTasks::Organizations::Base
      # Required as a result of `abstract` Sorbet annotation in `AbstractTask`
      def task_link; end
      def icon_path; end
      def title; end
      def verify_task; end
    end

    class OrganizationsBaseTest < GitHub::TestCase
      fixtures do
        @owner = create(:user)
        @org = create(:organization, login: "ACME", admin: @owner)
      end

      setup do
        if GitHub.enterprise?
          GitHub::Plan.stubs(:business).raises(StandardError.new("No plan found for business"))
          GitHub::Plan.stubs(:business_plus).raises(StandardError.new("No plan found for business_plus"))
        end
      end

      context "#enabled_for_plan?" do
        if GitHub.enterprise?
          test "tasks are not enabled for enterprise server" do
            Onboard.stub_const(:GHEC_TASKS, [SomeTask]) do
              refute SomeTask.new(user: @owner, taskable: @org).enabled_for_plan?
            end
          end
        else
          test "free plan" do
            @org.update!(plan: GitHub::Plan.free)
            Onboard.stub_const(:FREE_TASKS, [SomeTask]) do
              assert SomeTask.new(user: @owner, taskable: @org).enabled_for_plan?
            end
          end

          test "free_with_addons plan" do
            @org.update!(plan: GitHub::Plan.free_with_addons)
            Onboard.stub_const(:FREE_TASKS, [SomeTask]) do
              assert SomeTask.new(user: @owner, taskable: @org).enabled_for_plan?
            end
          end

          test "team plan" do
            @org.update!(plan: GitHub::Plan.business)
            Onboard.stub_const(:TEAM_TASKS, [SomeTask]) do
              assert SomeTask.new(user: @owner, taskable: @org).enabled_for_plan?
            end
          end

          test "GHEC plan" do
            @org.update!(plan: GitHub::Plan.business_plus)
            Onboard.stub_const(:GHEC_TASKS, [SomeTask]) do
              assert SomeTask.new(user: @owner, taskable: @org).enabled_for_plan?
            end
          end
        end
      end
    end
  end
end
