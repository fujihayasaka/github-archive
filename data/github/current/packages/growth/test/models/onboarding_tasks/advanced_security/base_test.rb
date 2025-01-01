# typed: true
# frozen_string_literal: true

require "test_helper"

module OnboardingTasks
  module AdvancedSecurity
    class SampleTask < Base
      def verify_task
        T.unsafe(taskable).verify
      end

      # Required as a result of `abstract` Sorbet annotation in `AbstractTask`
      def task_link; end
      def icon_path; end
      def title; end
    end

    class AdvancedSecurityBaseTest < GitHub::TestCase
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
          SampleTask.new(taskable: @org, user: @owner).complete

          assert_equal [:sample_task], @org.reload.completed_onboarding_tasks
        end

        test "publishes a hydro event" do
          SampleTask.new(taskable: @org, user: @owner).complete

          assert_hydro_published({
            user: Hydro::EntitySerializer.user(@owner),
            type: "advanced_security",
            task: "sample_task",
            completed_tasks: ["sample_task"],
            remaining_tasks: [],
            taskable_type: "Organization",
            taskable_id: @org.id,
          }, schema: "github.v1.OnboardingTaskCompleted")
        end
      end
    end
  end
end
