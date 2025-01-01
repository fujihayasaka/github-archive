# typed: true
# frozen_string_literal: true

require "test_helper"

module OnboardingTasks
  class SampleTask < AbstractTask
    def verify_task
      T.unsafe(taskable).verify
    end

    # Required as a result of `abstract` Sorbet annotation in `AbstractTask`
    def task_link; end
    def icon_path; end
    def title; end
  end

  class AbstractTaskTest < GitHub::TestCase
    include HydroTestHelpers

    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
    fixtures do
      @owner = create(:user)
      @org = create(:organization, login: "ACME", admin: @owner)
      @verify_stub = stub(completed_onboarding_tasks: [], verify: true)
    end

    context ".task_key" do
      test "returns the task key ignoring the namespace" do
        assert_equal :sample_task, SampleTask.task_key
      end
    end

    context "#completed?" do
      test "does not verify if already completed" do
        @org.update(completed_onboarding_tasks: [:sample_task])

        assert SampleTask.new(taskable: @org, user: @owner).completed?
      end

      test "verifies the task if not completed yet and stores it" do
        @org.expects(:verify).returns(true)
        @org.update(completed_onboarding_tasks: [])

        assert SampleTask.new(taskable: @org, user: @owner).completed?
        assert_equal [:sample_task], @org.reload.completed_onboarding_tasks
      end
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
          type: SampleTask.context,
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
