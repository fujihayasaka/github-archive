# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/missing_record_helper"

class Copilot::SeatManagement::UserJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  include MissingRecordHelper
  include HydroTestHelpers

  setup do
    GitHub.flipper[:copilot_seat_assignment_job].enable
  end

  context "destroy" do
    test "does nothing for user with no organizations" do
      user = create(:user)
      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count + Copilot::SeatAssignment.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::UserJob.perform_now(
              action: :destroy,
              transaction_id: "1234",
              payload: { foo: "bar" },
              user_id: user.id,
            )
          end
        end
      end

      assert_match "No CFB Seats Found For User", logs
      assert_match "No User Level CFB Seat Assignments For User", logs
    end

    test "does nothing for user with organization with no seats for user" do
      user = create(:user)
      organization = create(:organization)
      organization.add_member(user)

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count + Copilot::SeatAssignment.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::UserJob.perform_now(
              action: :destroy,
              transaction_id: "1234",
              payload: { foo: "bar" },
              user_id: user.id,
            )
          end
        end
      end

      assert_match "No CFB Seats Found For User", logs
      assert_match "No User Level CFB Seat Assignments For User", logs
    end

    test "does nothing for user with organization with seat assignment but no seats for user" do
      user = create(:user)
      organization = create(:organization)
      organization.add_member(user)
      team = create(:team, organization: organization)
      seat_assignment = create(:copilot_seat_assignment, assignable: team, organization: organization, assigning_user: organization.admins.first)

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count + Copilot::SeatAssignment.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::UserJob.perform_now(
              action: :destroy,
              transaction_id: "1234",
              payload: { foo: "bar" },
              user_id: user.id,
            )
          end
        end
      end

      assert Copilot::SeatAssignment.exists?(seat_assignment.id)
      assert_match "No CFB Seats Found For User", logs
      assert_match "No User Level CFB Seat Assignments For User", logs
    end

    test "deletes seat assignment for user" do
      user = create(:user)
      organization = create(:organization)
      organization.add_member(user)
      seat_assignment = create(:copilot_seat_assignment, assignable: user, organization: organization, assigning_user: organization.admins.first)

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::UserJob.perform_now(
              action: :destroy,
              transaction_id: "1234",
              payload: { foo: "bar" },
              user_id: user.id,
            )
          end
        end
      end

      refute Copilot::SeatAssignment.exists?(seat_assignment.id)

      assert_match "No CFB Seats Found For User", logs
      assert_match "Loaded User Level CFB Seat Assignments For User", logs
    end

    test "deletes seat assignment and seat for user" do
      user = create(:user)
      organization = create(:organization)
      organization.add_member(user)
      seat_assignment = create(:copilot_seat_assignment, assignable: user, organization: organization, assigning_user: organization.admins.first)
      seat_assignment.convert_to_seats
      seat = seat_assignment.seats.first

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::UserJob.perform_now(
            action: :destroy,
            transaction_id: "1234",
            payload: { foo: "bar" },
            user_id: user.id,
          )
        end
      end

      refute Copilot::SeatAssignment.exists?(seat_assignment.id)
      refute Copilot::Seat.exists?(seat.id)

      assert_match "Loaded CFB Seats for User", logs
      assert_match "Loaded User Level CFB Seat Assignments For User", logs
    end
  end
end if GitHub.copilot_enabled?
