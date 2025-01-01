# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/missing_record_helper"

class Copilot::SeatManagement::SeatAssignmentConvererJobTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include GitHub::LoggerHelper
  include JobTestHelper
  include MissingRecordHelper

  setup do
    GitHub.flipper[:copilot_seat_assignment_job].enable
  end

  test "it will handle an error" do
    Copilot::ErrorReporter.expects(:report!).once
    Copilot::SeatAssignments::UserConverterCommand.any_instance.stubs(:call).raises(StandardError)
    pending_seat_assignment = create(:copilot_seat_assignment, :user)
    Copilot::SeatManagement::SeatAssignmentConverterJob.perform_now(seat_assignment_id: pending_seat_assignment.id)
  end

  test "it will handle a missing seat assignment" do
    logs = capture_logs do
      Copilot::SeatManagement::SeatAssignmentConverterJob.perform_now(seat_assignment_id: 123)
    end
    assert_includes logs, "SeatAssignment not found"
  end

  test "it goes all the way" do
    logs = capture_logs do
      assert_changes -> { Copilot::Seat.count }, from: 0, to: 1 do
        pending_seat_assignment = create(:copilot_seat_assignment, :user)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::SeatAssignmentConverterJob.perform_now(seat_assignment_id: pending_seat_assignment.id)
        end
      end
    end
    assert_includes logs, "Creating new Seat for this User and Owner"
    assert_includes logs, "Inserting seats"
  end
end if GitHub.copilot_enabled?
