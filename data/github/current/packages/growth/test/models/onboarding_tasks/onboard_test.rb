# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  class OnboardTest < GitHub::TestCase
    fixtures do
      @owner = create(:user)
      @org = create(:organization, admin: @owner)
    end

    context ".percentage_completed" do
      test "returns the completed percentage of tasks" do
        all_tasks = Onboard::ALL_BY_CONTEXT[:organizations].map(&:task_key)

        assert_equal 0, Onboard.percentage_completed(@org, :organizations)

        @org.update!(completed_onboarding_tasks: all_tasks)

        assert_equal 100, Onboard.percentage_completed(@org, :organizations)
      end
    end

    context ".remaining_tasks" do
      test "returns remaining tasks" do
        all_tasks = Onboard::ALL_BY_CONTEXT[:organizations]
        completed_task = all_tasks.first.new(taskable: @org, user: @owner)
        completed_task.complete

        remaining_tasks = Onboard.remaining_tasks(@org, @owner, :organizations)

        refute remaining_tasks.include?(completed_task.task_key)
        assert remaining_tasks.include?(all_tasks.last.task_key)
      end
    end

    context "#task" do
      test "finds the task under the right context" do
        task = Onboard.new(@org, @owner).task(task_key: :invite_member, context: :organizations)

        assert task.is_a?(Organizations::InviteMember)
      end

      test "returns nil if task is not found" do
        task = Onboard.new(@org, @owner).task(task_key: :unknown_task, context: :organizations)

        assert_nil task
      end

      test "returns a task with passed attributes" do
        task = Onboard.new(@org, @owner).task(task_key: :invite_member, context: :organizations, attributes: { country_code: "BRA" })

        assert task.is_a?(Organizations::InviteMember)
        assert_equal task.attributes, { country_code: "BRA" }
      end
    end
  end
end
