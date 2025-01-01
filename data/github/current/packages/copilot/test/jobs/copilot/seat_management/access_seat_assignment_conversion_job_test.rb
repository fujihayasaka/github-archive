# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::SeatManagement::AccessSeatAssignmentConversionJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:perform_later).never
    GitHub.flipper[:copilot_seat_assignment_job].enable
    GitHub.flipper[:copilot_access_seat_assignment_conversion_job].enable
  end

  context "perform" do
    test "requires BOTH flags" do
      GitHub.flipper[:copilot_access_seat_assignment_conversion_job].disable
      assert_logged("Body" => "Skipping Copilot::SeatManagement::AccessSeatAssignmentConversionJob") do
        Copilot::SeatManagement::AccessSeatAssignmentConversionJob.perform_now(
          user_id: 233552342,
          headers: {},
        )
      end
    end

    test "does nothing with fake user" do
      Copilot::ErrorReporter.expects(:report!).with do |error, context|
        error.is_a?(Copilot::Errors::CopilotError) &&
        context[:extra_details]["gh.user.id"] == 233552342
      end
      assert_logged("Body" => "Invalid User") do
        Copilot::SeatManagement::AccessSeatAssignmentConversionJob.perform_now(
          user_id: 233552342,
          headers: {},
        )
      end
    end

    test "loads a bunch of seat assignments if none passed" do
      user = create(:user)
      org = create(:organization)
      org.add_member(user)
      team = create(:team, organization: org)
      team.add_member(user)
      create(:copilot_seat_assignment, organization: org, assignable: team)

      assert_logged("Body" => "Queueing immediate seat assignment conversion") do
        Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:perform_later).once
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::AccessSeatAssignmentConversionJob.perform_now(
            user_id: user.id,
            headers: {},
          )
        end
      end
    end

    test "doesn't convert seat assignments that are already converted" do
      seat = create(:copilot_seat)
      user = seat.assigned_user

      assert_logged("Body" => "Found seat assignments to be converted") do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::AccessSeatAssignmentConversionJob.perform_now(
            user_id: user.id,
            headers: {},
          )
        end
      end
    end

    test "handles copilot standalone business" do
      GitHub.flipper[:copilot_seat_assignment_job].enable
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      enterprise_team = assignment.assignable
      user = User.find(enterprise_team.member_user_ids.first)

      Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:perform_later).once
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::AccessSeatAssignmentConversionJob.perform_now(
          user_id: user.id,
          headers: {},
        )
      end
    end

    test "doesn't convert seat assignments for suspended users with User seat assignments" do
      GitHub.flipper[:copilot_seat_assignment_job].enable
      user = create(:user)
      org = create(:organization)
      org.add_member(user)

      user_seat_assignment = create(:copilot_seat_assignment, :user, organization: org, assignable: user)
      user.update_column(:suspended_at, Time.current)
      refute user_seat_assignment.requires_conversion?

      Copilot::ErrorReporter.expects(:report!).with do |error, context|
        error.is_a?(Copilot::Errors::CopilotError) &&
        context[:extra_details]["gh.user.id"] == user.id
      end
      Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:perform_later).never
      refute_logged("Body" => "Queueing immediate seat assignment conversion") do
        assert_logged("Body" => "Triggering seat assignment conversion for a suspended user") do
          Copilot::SeatManagement::AccessSeatAssignmentConversionJob.perform_now(
            user_id: user.id,
            headers: {},
          )
        end
      end
    end
  end
end if GitHub.copilot_enabled?
