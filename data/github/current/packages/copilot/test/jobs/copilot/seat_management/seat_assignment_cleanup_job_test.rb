# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::SeatManagement::SeatAssignmentCleanupJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include DogstatsTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    GitHub.flipper[:user_sa_to_team_sa_cleanup_job].disable
  end

  context "perform" do
    test "it will do nothing if there is nothing to do" do
      GitHub.flipper[:copilot_seat_assignment_job].enable
      assert_no_changes -> { Copilot::SeatAssignment.count + Copilot::Seat.count } do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::SeatAssignmentCleanupJob.perform_now(0)
        end
      end

      not_pending_seat_assignment = create(:copilot_seat_assignment, :organization)
      not_pending_seat_assignment.convert_to_seats

      logs = capture_logs do
        assert_no_changes -> { Copilot::SeatAssignment.count + Copilot::Seat.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::SeatAssignmentCleanupJob.perform_now(not_pending_seat_assignment.id)
          end
        end
      end

      assert_includes logs, "gh.seat_assignment.pending_cancellation_today?=\"false\""
    end

    context "user_sa_to_team_sa_cleanup_job feature flag disabled" do
      test "it will cancel the seat and not repoint it to the team seat assignment if the user is a member of a team that has a SeatAssignment that is not pending cancellation" do
        GitHub.flipper[:copilot_seat_assignment_job].enable
        GitHub.flipper[:user_sa_to_team_sa_cleanup_job].disable

        org = create(:organization)
        team = create(:team, organization: org)
        user = create(:user)
        org.add_member(user)
        team.add_member(user)

        create(:copilot_seat_assignment, :team, assignable: team, organization: org)
        user_seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: org)
        user_seat = create(:copilot_seat, assigned_user: user, seat_assignment: user_seat_assignment, organization: org)
        user_seat_assignment.update!(pending_cancellation_date: Date.today)

        logs = capture_logs do
          assert_difference -> { Copilot::SeatAssignment.count }, -1 do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::SeatAssignmentCleanupJob.perform_now(user_seat_assignment.id)
            end
          end
        end

        assert_includes logs, "gh.seat_assignment.pending_cancellation_today?=\"true\""
        refute_includes logs, "Found Team SeatAssignment containing user that is not pending cancellation. Not cancelling their seat."
        refute_includes logs, "User not found in any other active SeatAssignment. Cancelling user's seat."
        assert_includes logs, "Cancelling associated seat"
        assert_includes logs, "Destroying SeatAssignment"
        refute Copilot::SeatAssignment.exists?(user_seat_assignment.id)
        refute Copilot::Seat.exists?(user_seat.id)
        refute_dogstats_increment("copilot.seat_assignment_cleanup.other_active_assignment_found", tags: ["type: team"])
        assert_dogstats_increment(1, "copilot.seat_assignment_cleanup.to_be_cleaned_up", tags: ["type: user"])
        assert_dogstats_increment(1, "copilot.seat_assignment_cleanup.seat_cancelled")
      end

      test "it will cancel seats with trial_seat passed down" do
        freeze_time do
          GitHub.flipper[:copilot_seat_assignment_job].enable
          GitHub.flipper[:user_sa_to_team_sa_cleanup_job].disable
          pending_seat_assignment = create(:copilot_seat_assignment, :user)
          pending_seat_assignment.convert_to_seats

          assert_equal 1, pending_seat_assignment.seats.count

          pending_seat_assignment.update!(pending_cancellation_date: Date.today)

          pending_seat_assignment.seats do |seat|
            seat.expects(:cancel!).with(trial_seat: true, reason: :seat_assignment_cleaned_up).once
          end
          logs = capture_logs do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::SeatAssignmentCleanupJob.perform_now(pending_seat_assignment.id, trial_seats: true)
            end
          end
          refute Copilot::SeatAssignment.exists?(pending_seat_assignment.id)
          assert_equal 0, Copilot::Seat.count

          assert_includes logs, "gh.copilot.organization.trial=\"true"
          assert_dogstats_increment(1, "copilot.seat_assignment_cleanup.seat_cancelled", tags: ["trial_seats: true"])
        end
      end
    end

    context "user_sa_to_team_sa_cleanup_job feature flag enabled" do
      test "it will repoint user's seat to the team seat assignment if the user is a member of a team that has a SeatAssignment that is not pending cancellation" do
        GitHub.flipper[:user_sa_to_team_sa_cleanup_job].enable
        GitHub.flipper[:copilot_seat_assignment_job].enable

        org = create(:organization)
        team = create(:team, organization: org)
        user = create(:user)
        org.add_member(user)
        team.add_member(user)

        team_seat_assignment = create(:copilot_seat_assignment, :team, assignable: team, organization: org)
        user_seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: org)
        user_seat_assignment.convert_to_seats
        user_seat_assignment.update!(pending_cancellation_date: Date.today)

        logs = capture_logs do
          assert_difference -> { Copilot::SeatAssignment.count }, -1 do
            assert_no_changes -> { Copilot::Seat.count } do
              ActiveRecord::Base.connected_to(role: :reading) do
                Copilot::SeatManagement::SeatAssignmentCleanupJob.perform_now(user_seat_assignment.id)
              end
            end
          end
        end

        assert_includes logs, "gh.seat_assignment.pending_cancellation_today?=\"true\""
        assert_includes logs, "Updating user's seat to point at the active SeatAssignment"
        assert_includes logs, "gh.copilot.seat_assignment.id=\"#{user_seat_assignment.id}\""
        assert_includes logs, "gh.copilot.other_seat_assignment.id=\"#{team_seat_assignment.id}\""
        refute_includes logs, "Cancelling associated seat"
        assert_includes logs, "Destroying SeatAssignment"
        refute Copilot::SeatAssignment.exists?(user_seat_assignment.id)
        assert_equal team_seat_assignment.id, Copilot::Seat.where(assigned_user_id: user.id).first.seat_assignment.id
        assert_dogstats_increment(1, "copilot.seat_assignment_cleanup.other_active_assignment_found", tags: ["type: team"])
        assert_dogstats_increment(1, "copilot.seat_assignment_cleanup.to_be_cleaned_up", tags: ["type: user"])
        refute_dogstats_increment("copilot.seat_assignment_cleanup.seat_cancelled")
      end

      test "it will repoint user's seat to the team seat assignment if the user is a member of a team that has a SeatAssignment that is pending cancellation in the future" do
        GitHub.flipper[:user_sa_to_team_sa_cleanup_job].enable
        GitHub.flipper[:copilot_seat_assignment_job].enable

        org = create(:organization)
        team = create(:team, organization: org)
        user = create(:user)
        org.add_member(user)
        team.add_member(user)

        team_seat_assignment = create(:copilot_seat_assignment, :team, assignable: team, organization: org)
        user_seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: org)
        user_seat_assignment.convert_to_seats

        user_seat_assignment.update!(pending_cancellation_date: Date.today)
        team_seat_assignment.update!(pending_cancellation_date: Date.today + 5.days)

        logs = capture_logs do
          assert_difference -> { Copilot::SeatAssignment.count }, -1 do
            assert_no_changes -> { Copilot::Seat.count } do
              ActiveRecord::Base.connected_to(role: :reading) do
                Copilot::SeatManagement::SeatAssignmentCleanupJob.perform_now(user_seat_assignment.id)
              end
            end
          end
        end

        assert_includes logs, "gh.seat_assignment.pending_cancellation_today?=\"true\""
        assert_includes logs, "Updating user's seat to point at the active SeatAssignment"
        refute_includes logs, "Cancelling associated seat"
        assert_includes logs, "Destroying SeatAssignment"
        refute Copilot::SeatAssignment.exists?(user_seat_assignment.id)
        assert_equal team_seat_assignment.id, Copilot::Seat.where(assigned_user_id: user.id).first.seat_assignment.id
        assert_dogstats_increment(1, "copilot.seat_assignment_cleanup.other_active_assignment_found", tags: ["type: team"])
        assert_dogstats_increment(1, "copilot.seat_assignment_cleanup.to_be_cleaned_up", tags: ["type: user"])
        refute_dogstats_increment("copilot.seat_assignment_cleanup.seat_cancelled")
      end

      test "it will repoint user's seat to the organization seat assignment if the user is a member of a organization that has a SeatAssignment that is not pending cancellation" do
        GitHub.flipper[:user_sa_to_team_sa_cleanup_job].enable
        GitHub.flipper[:copilot_seat_assignment_job].enable

        org = create(:organization)
        user = create(:user)
        org.add_member(user)

        org_seat_assignment = create(:copilot_seat_assignment, :organization, assignable: org, organization: org)
        user_seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: org)
        user_seat_assignment.convert_to_seats
        user_seat_assignment.update!(pending_cancellation_date: Date.today)

        logs = capture_logs do
          assert_difference -> { Copilot::SeatAssignment.count }, -1 do
            assert_no_changes -> { Copilot::Seat.count } do
              ActiveRecord::Base.connected_to(role: :reading) do
                Copilot::SeatManagement::SeatAssignmentCleanupJob.perform_now(user_seat_assignment.id)
              end
            end
          end
        end

        assert_includes logs, "gh.seat_assignment.pending_cancellation_today?=\"true\""
        assert_includes logs, "Updating user's seat to point at the active SeatAssignment"
        refute_includes logs, "Cancelling associated seat"
        assert_includes logs, "Destroying SeatAssignment"
        refute Copilot::SeatAssignment.exists?(user_seat_assignment.id)
        assert_equal org_seat_assignment.id, Copilot::Seat.where(assigned_user_id: user.id).first.seat_assignment.id
        assert_dogstats_increment(1, "copilot.seat_assignment_cleanup.other_active_assignment_found", tags: ["type: organization"])
        assert_dogstats_increment(1, "copilot.seat_assignment_cleanup.to_be_cleaned_up", tags: ["type: user"])
        refute_dogstats_increment("copilot.seat_assignment_cleanup.seat_cancelled", tags: ["trial_seats: false"])
      end

      test "it will cancel the seat and not repoint it if the user is a member of a team that has a SeatAssignment that is also pending cancellation" do
        GitHub.flipper[:copilot_seat_assignment_job].enable
        GitHub.flipper[:user_sa_to_team_sa_cleanup_job].enable

        org = create(:organization)
        team = create(:team, organization: org)
        user = create(:user)
        other_user = create(:user)
        org.add_member(user)
        team.add_member(user)
        org.add_member(other_user)
        team.add_member(other_user)

        team_seat_assignment = create(:copilot_seat_assignment, :team, assignable: team, organization: org)
        user_seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: org)

        user_seat_assignment.update!(pending_cancellation_date: Date.today)
        team_seat_assignment.update!(pending_cancellation_date: Date.today)

        user_seat = create(:copilot_seat, seat_assignment: user_seat_assignment, organization: org, assigned_user: user)
        other_user_seat = create(:copilot_seat, seat_assignment: team_seat_assignment, organization: org, assigned_user: other_user)

        assert_equal 2, Copilot::Seat.count

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::SeatAssignmentCleanupJob.perform_now(user_seat_assignment.id)
          end
        end

        assert_includes logs, "gh.seat_assignment.pending_cancellation_today?=\"true\""
        refute_includes logs, "Found Team SeatAssignment containing user that is not pending cancellation. Not cancelling their seat."
        assert_includes logs, "User not found in any other active SeatAssignment. Cancelling user's seat."
        assert_includes logs, "Destroying SeatAssignment"
        refute Copilot::SeatAssignment.exists?(user_seat_assignment.id)
        refute Copilot::Seat.exists?(user_seat.id)
        assert Copilot::Seat.exists?(other_user_seat.id)
        assert_equal 1, Copilot::Seat.count
        refute_dogstats_increment("copilot.seat_assignment_cleanup.other_active_assignment_found", tags: ["type: team"])
        assert_dogstats_increment(1, "copilot.seat_assignment_cleanup.to_be_cleaned_up", tags: ["type: user"])
        assert_dogstats_increment(1, "copilot.seat_assignment_cleanup.seat_cancelled")
      end
    end

    test "it will remove any seats for a user seat assignment not associated with any other assignment" do
      freeze_time do
        GitHub.flipper[:copilot_seat_assignment_job].enable
        GitHub.flipper[:user_sa_to_team_sa_cleanup_job].enable
        pending_seat_assignment = create(:copilot_seat_assignment, :user)
        pending_seat_assignment.convert_to_seats

        assert_equal 1, pending_seat_assignment.seats.count

        pending_seat_assignment.update!(pending_cancellation_date: Date.today)

        pending_seat_assignment.seats do |seat|
          seat.expects(:cancel!).with(trial_seat: false, reason: :seat_assignment_cleaned_upe).once
        end
        expected_cancelled_seat_id = pending_seat_assignment.seats.first.id

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::SeatAssignmentCleanupJob.perform_now(pending_seat_assignment.id)
          end
        end

        assert_includes logs, "User not found in any other active SeatAssignment. Cancelling user's seat."
        assert_includes logs, "gh.copilot.seat.id=\"#{expected_cancelled_seat_id}\""
        refute Copilot::SeatAssignment.exists?(pending_seat_assignment.id)
        assert_equal 0, Copilot::Seat.count
        assert_dogstats_increment("copilot.seat_assignment_cleanup.seat_cancelled", tags: ["trial_seats: false"])
      end
    end

    test "it will cancel seats with trial_seat passed down" do
      freeze_time do
        GitHub.flipper[:copilot_seat_assignment_job].enable
        GitHub.flipper[:user_sa_to_team_sa_cleanup_job].enable
        pending_seat_assignment = create(:copilot_seat_assignment, :user)
        pending_seat_assignment.convert_to_seats

        assert_equal 1, pending_seat_assignment.seats.count

        pending_seat_assignment.update!(pending_cancellation_date: Date.today)

        pending_seat_assignment.seats do |seat|
          seat.expects(:cancel!).with(trial_seat: true, reason: :seat_assignment_cleaned_up).once
        end
        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::SeatAssignmentCleanupJob.perform_now(pending_seat_assignment.id, trial_seats: true)
          end
        end
        refute Copilot::SeatAssignment.exists?(pending_seat_assignment.id)
        assert_equal 0, Copilot::Seat.count

        assert_includes logs, "gh.copilot.organization.trial=\"true"
        assert_dogstats_increment("copilot.seat_assignment_cleanup.seat_cancelled", tags: ["trial_seats: true"])
      end
    end
  end
end if GitHub.copilot_enabled?
