# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module EnterpriseCloudOnboard
  class OnboardTasksTest < GitHub::TestCase
    fixtures do
      @org = create(:organization, login: "ACME")
    end

    context ".next_uncompleted_task" do
      test "returns the next uncompleted task" do
        @org.update(completed_onboarding_tasks: [:auto_assign_issue, :run_ci])

        assert_equal OnboardingTasks::Organizations::BranchProtectionRule, OnboardingTasks::Onboard.next_uncompleted_task_for_context(@org, @org.admin, :organizations).class
      end unless GitHub.enterprise?
    end
  end
end
