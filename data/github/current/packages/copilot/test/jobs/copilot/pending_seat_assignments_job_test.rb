# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::PendingSeatAssignmentsJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "perform" do
    test "it will do nothing if flag is disabled" do
      disable_feature_flag(:copilot_seat_assignment_job)
      Copilot::SeatManagement::SeatAssignmentCleanupJob.expects(:perform_later).never
      logs = capture_logs do
        Copilot::PendingSeatAssignmentsJob.perform_now
      end
      assert_match "Skipping Copilot::PendingSeatAssignmentsJob", logs
    end

    test "it will do nothing if there is nothing to do" do
      enable_feature_flag(:copilot_seat_assignment_job)
      Copilot::SeatManagement::SeatAssignmentCleanupJob.expects(:perform_later).never
      Copilot::PendingSeatAssignmentsJob.perform_now
    end

    test "it will remove any seats for a user seat assignment" do
      freeze_time do
        enable_feature_flag(:copilot_seat_assignment_job)
        pending_seat_assignment = create(:copilot_seat_assignment, :user)
        pending_seat_assignment.convert_to_seats

        assert_equal 1, pending_seat_assignment.seats.count

        pending_seat_assignment.update!(pending_cancellation_date: Date.today)
        Copilot::SeatManagement::SeatAssignmentCleanupJob.expects(:perform_later).once
        Copilot::PendingSeatAssignmentsJob.perform_now
      end
    end
  end
end if GitHub.copilot_enabled?
