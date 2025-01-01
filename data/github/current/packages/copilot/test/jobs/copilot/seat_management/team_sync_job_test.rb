# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/missing_record_helper"

class Copilot::SeatManagement::TeamSyncJobTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include GitHub::LoggerHelper
  include JobTestHelper
  include DogstatsTestHelpers

  fixtures do
    @organization = create(:organization)
    @team = create(:team, organization: @organization)
    @suspended_user = create(:user, suspended_at: Time.now)
    5.times do
      user = create(:user)
      @team.add_member(user)
    end
    @team.add_member(@suspended_user)

    @team_seat_assignment = create(:copilot_seat_assignment, assignable: @team, organization: @organization)

    @enterprise_team_seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    @enterprise_team = @enterprise_team_seat_assignment.assignable

    @org_for_assignment = create(:organization)
    5.times do
      user = create(:user)
      @org_for_assignment.add_member(user)
    end
    @org_seat_assignment = create(:copilot_seat_assignment, assignable: @org_for_assignment, organization: @org_for_assignment)
  end

  setup do
    GitHub.flipper[:copilot_seat_assignment_job].enable
    GitHub.flipper[:copilot_team_sync_job].enable
    @total_members_eligible_for_seats = @team_seat_assignment.assignable_members_eligible_for_seats_count + @enterprise_team_seat_assignment.assignable_members_eligible_for_seats_count

    silence_warnings do
      ::Copilot::COPILOT_FOR_BUSINESS_SEAT_DELAYS = {
        ENTERPRISE_TEAM: 15.minutes,
        TEAM: 15.minutes,
      }
    end
  end

  test "does not run if the feature flag is disabled" do
    GitHub.flipper[:copilot_team_sync_job].disable
    logs = capture_logs do
      Copilot::SeatManagement::TeamSyncJob.perform_now
    end

    refute_includes logs, "Starting TeamSyncJob"
  end

  test "doesn't convert if assignment is in the cooling off period" do
    travel_to Time.current do
      @team_seat_assignment.update!(created_at: Time.now)
      @enterprise_team_seat_assignment.update!(created_at: Time.now)
    end

    travel_to 1.minute.from_now do
      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::TeamSyncJob.perform_now
          end
        end
      end

      assert_includes logs, "Starting TeamSyncJob"
      assert_dogstats_histogram_value(0, "copilot.seat_management.team_sync_job.assignments_to_convert")
    end
  end

  test "runs if there are no seats that need to be created" do
    @team_seat_assignment.convert_to_seats
    @enterprise_team_seat_assignment.convert_to_seats

    assert_equal @total_members_eligible_for_seats, Copilot::Seat.count

    travel_to 1.hour.from_now do
      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::TeamSyncJob.perform_now
          end
        end
      end

      assert_includes logs, "Starting TeamSyncJob"
      assert_includes logs, "No new seats need to be created"
      assert_dogstats_histogram_value(2, "copilot.seat_management.team_sync_job.assignments_to_convert")
      assert_dogstats_increment("copilot.seat_assignment_conversion.skipped", tags: ["type:team", "reason:no_difference"])
      assert_dogstats_increment("copilot.seat_assignment_conversion.skipped", tags: ["type:enterprise_team", "reason:no_difference"])
    end
  end

  test "converts all the seats" do
    assert_equal 0, Copilot::Seat.count
    assert_equal 3, Copilot::SeatAssignment.count

    travel_to 1.hour.from_now do
      logs = capture_logs do
        assert_changes -> { Copilot::Seat.count }, from: 0, to: @total_members_eligible_for_seats do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::TeamSyncJob.perform_now
          end
        end
      end

      assert_nil Copilot::Seat.find_by(assigned_user_id: @suspended_user.id)
      assert_equal 0, @org_seat_assignment.seats.count

      refute_includes logs, "No new seats need to be created"
      assert_includes logs, "New seats need to be created"
      assert_includes logs, "Inserted new seats for team members"

      assert_dogstats_histogram_value(5, "copilot.seat_assignment_conversion.difference", tags: ["type:team"])
      assert_dogstats_histogram_value(5, "copilot.seat_assignment_conversion.inserting", tags: ["type:team"])
      assert_dogstats_histogram_value(2, "copilot.seat_management.team_sync_job.assignments_to_convert")

      assert_dogstats_histogram_value(@enterprise_team.member_user_ids.count, "copilot.seat_assignment_conversion.difference", tags: ["type:enterprise_team"])
      assert_dogstats_histogram_value(@enterprise_team.member_user_ids.count, "copilot.seat_assignment_conversion.inserting", tags: ["type:enterprise_team"])
    end
  end
end if GitHub.copilot_enabled?
