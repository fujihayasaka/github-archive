# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::SeatManagement::AccessSeatAssignmentConversionJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:perform_later).never
    enable_feature_flag(:copilot_seat_assignment_job)
    enable_feature_flag(:copilot_access_seat_assignment_conversion_job)
  end

  context "perform" do
    test "requires BOTH flags" do
      disable_feature_flag(:copilot_access_seat_assignment_conversion_job)
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

    test "loads and converts a bunch of seat assignments" do
      user = create(:user)
      org = create(:organization)
      org.add_member(user)
      team = create(:team, organization: org)
      team.add_member(user)
      create(:copilot_seat_assignment, organization: org, assignable: team)

      org2 = create(:organization)
      org2.add_member(user)
      create(:copilot_seat_assignment, organization: org2, assignable: org2)

      assert_logged("Body" => "Queueing immediate seat assignment conversion via AccessSeatAssignmentConversionJob") do
        Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:perform_later).twice
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::AccessSeatAssignmentConversionJob.perform_now(
            user_id: user.id,
            headers: {},
          )
        end
      end

      assert_dogstats_increment(1, "copilot.seat_management.access_seat_assignment_conversion_job.seat_assignment_converted", tags: ["type:team"])
      assert_dogstats_increment(1, "copilot.seat_management.access_seat_assignment_conversion_job.seat_assignment_converted", tags: ["type:organization"])
    end

    test "doesn't convert seat assignments that are already converted" do
      seat = create(:copilot_seat)
      user = seat.assigned_user

      refute_logged("Body" => "Found seat assignments to be converted") do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::AccessSeatAssignmentConversionJob.perform_now(
            user_id: user.id,
            headers: {},
          )
        end
      end
    end

    test "handles copilot standalone business" do
      enable_feature_flag(:copilot_seat_assignment_job)
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
      assert_dogstats_increment(1, "copilot.seat_management.access_seat_assignment_conversion_job.seat_assignment_converted", tags: ["type:enterprise_team"])
    end

    test "doesn't convert seat assignments for suspended users with User seat assignments" do
      enable_feature_flag(:copilot_seat_assignment_job)
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
      refute_logged("Body" => "Queueing immediate seat assignment conversion via AccessSeatAssignmentConversionJob") do
        assert_logged("Body" => "Attempting to convert seat assignment for suspended user via AccessSeatAssignmentConversionJob") do
          Copilot::SeatManagement::AccessSeatAssignmentConversionJob.perform_now(
            user_id: user.id,
            headers: {},
          )
        end
      end
    end

    test "resolves tenant on a multi-tenant enterprise with business owner" do
      on_multi_tenant_enterprise do
        # Simulate no tenant being set
        GitHub::CurrentTenant.remove
        assert_nil GitHub::CurrentTenant.get

        emu = create(:emu)

        Copilot::SeatManagement::AccessSeatAssignmentConversionJob.perform_now(
          user_id: emu.id,
          headers: {},
        )

        assert_equal emu.enterprise_managed_business, GitHub::CurrentTenant.get
      end
    end
  end
end if GitHub.copilot_enabled?
