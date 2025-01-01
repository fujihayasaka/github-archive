# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::DeleteOrphanedSeatsJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    GitHub.flipper[:copilot_chatterbox].enable
  end

  context "perform" do
    test "it will do nothing if flag is disabled" do
      GitHub.flipper[:copilot_seat_assignment_job].disable
      logs = capture_logs do
        Copilot::DeleteOrphanedSeatsJob.perform_now
      end
      assert_match "Skipping Copilot::DeleteOrphanedSeatsJob", logs
    end

    test "it will remove any seats for a user seat assignment" do
      freeze_time do
        GitHub.flipper[:copilot_seat_assignment_job].enable
        seat_assignment_to_delete = create(:copilot_seat_assignment, :user)
        seat_assignment_to_remain = create(:copilot_seat_assignment, :user)
        [seat_assignment_to_delete, seat_assignment_to_remain].each(&:convert_to_seats)
        seat_id = seat_assignment_to_delete.seats.first.id
        seat_assignment_to_delete.destroy

        assert Copilot::Seat.exists?(copilot_seat_assignment_id: seat_assignment_to_delete.id)
        logs = capture_logs do
          assert_changes -> { Copilot::Seat.count }, from: 2, to: 1 do
            Copilot::DeleteOrphanedSeatsJob.perform_now
          end
        end
        assert_match "Deleting orphaned Seat", logs
        assert_match "gh.copilot.seat.id=\"#{seat_id}\"", logs
        refute Copilot::Seat.exists?(copilot_seat_assignment_id: seat_assignment_to_delete.id)
        assert Copilot::Seat.exists?(copilot_seat_assignment_id: seat_assignment_to_remain.id)
      end
    end
  end
end if GitHub.copilot_enabled?
