# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/missing_record_helper"

class Copilot::SeatManagement::InstrumentSeatAssignmentScheduledCancellationJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  include HydroTestHelpers
  include MissingRecordHelper

  context "perform" do
    test "bails if there are no seat assignments" do
      logs = capture_logs do
        Copilot::SeatManagement::InstrumentSeatAssignmentScheduledCancellationJob.perform_now(
          [missing(:organization).id],
          nil,
          :seat_management_disabled
        )
      end

      assert_match "No seat assignments found", logs
    end

    test "logs when no actor is supplied" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      assignment = create(:copilot_seat_assignment, organization: org, assignable: user)

      logs = capture_logs do
        Copilot::SeatManagement::InstrumentSeatAssignmentScheduledCancellationJob.perform_now(
          [assignment.id],
          nil,
          :seat_management_disabled
        )
      end

      assert_match "Unassignment not triggered by an actor", logs
    end

    test "instruments seat assignment unassigned" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      assignment = create(:copilot_seat_assignment, organization: org, assignable: user)

      Copilot::Instrumenter
        .expects(:instrument_copilot_for_business_seat_assignment_unassigned)
        .once
        .with(assignment, nil, :seat_management_disabled)

      Copilot::SeatManagement::InstrumentSeatAssignmentScheduledCancellationJob.perform_now(
        [assignment.id],
        nil,
        :seat_management_disabled
      )
    end
  end
end
