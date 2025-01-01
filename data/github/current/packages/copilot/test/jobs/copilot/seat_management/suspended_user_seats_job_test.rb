# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::SeatManagement::SuspendedUserSeatsJobJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  include DogstatsTestHelpers

  context "perform" do
    context "with :copilot_revokable_access flag disabled" do
      test "it will cancel seats for suspended users who are part of an org with a seat assignment" do
        enable_feature_flag(:suspended_user_seats_job)
        disable_feature_flag(:copilot_revokable_access)
        freeze_time do
          org = create(:copilot_for_business_enabled_organization)
          suspended_user = create(:user)
          normal_user = create(:user)
          org.add_member(suspended_user)
          org.add_member(normal_user)

          org_seat_assignment = create(:copilot_seat_assignment, assignable: org, organization: org)
          org_seat_assignment.convert_to_seats

          suspended_user.update_column(:suspended_at, Time.current)

          suspended_user_seat = Copilot::Seat.find_by(assigned_user_id: suspended_user.id)

          assert_equal 3, Copilot::Seat.count # includes org admin

          logs = capture_logs do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::SuspendedUserSeatsJob.perform_now
            end
          end

          assert_equal 2, Copilot::Seat.count
          assert_includes logs, "Running SuspendedUserSeatsJob"
          assert_includes logs, "Processing seat for suspended user"
          assert_includes logs, "gh.copilot.seat.id=\"#{suspended_user_seat&.id}"
          assert_includes logs, "gh.copilot.seat_assignment.owner.id=\"#{org.id}"
          assert_includes logs, "gh.copilot.seat_assignment.owner_type=\"Organization"
          assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"Organization"
          assert_nil Copilot::Seat.find_by(assigned_user_id: suspended_user.id)
          refute_nil Copilot::SeatAssignment.find_by(id: org_seat_assignment.id)
          assert_dogstats_increment(1, "copilot.seat_management.suspended_user_seats_job.suspended_user_seat_destroyed")
        end
      end

      test "it will cancel seats for suspended users who are part of a team with a seat assignment" do
        enable_feature_flag(:suspended_user_seats_job)
        disable_feature_flag(:copilot_revokable_access)
        freeze_time do
          org = create(:copilot_for_business_enabled_organization)
          suspended_user = create(:user)
          normal_user = create(:user)
          org.add_member(suspended_user)
          org.add_member(normal_user)

          team = create(:team, organization: org)
          team.add_member(suspended_user)
          team.add_member(normal_user)

          team_seat_assignment = create(:copilot_seat_assignment, assignable: team, organization: org)
          team_seat_assignment.convert_to_seats

          suspended_user.update_column(:suspended_at, Time.current)

          suspended_user_seat = Copilot::Seat.find_by(assigned_user_id: suspended_user.id)

          assert_equal 2, Copilot::Seat.count # includes org admin

          logs = capture_logs do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::SuspendedUserSeatsJob.perform_now
            end
          end

          assert_equal 1, Copilot::Seat.count
          assert_includes logs, "Processing seat for suspended user"
          assert_includes logs, "Running SuspendedUserSeatsJob"
          assert_includes logs, "gh.copilot.seat.id=\"#{suspended_user_seat&.id}"
          assert_includes logs, "gh.copilot.seat_assignment.owner.id=\"#{org.id}"
          assert_includes logs, "gh.copilot.seat_assignment.owner_type=\"Organization"
          assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"Team"
          assert_nil Copilot::Seat.find_by(assigned_user_id: suspended_user.id)
          refute_nil Copilot::SeatAssignment.find_by(id: team_seat_assignment.id)
          assert_dogstats_increment(1, "copilot.seat_management.suspended_user_seats_job.suspended_user_seat_destroyed")
        end
      end

      test "it will cancel seats for suspended users with User seat assignments" do
        enable_feature_flag(:suspended_user_seats_job)
        disable_feature_flag(:copilot_revokable_access)
        freeze_time do
          org = create(:copilot_for_business_enabled_organization)
          suspended_user = create(:user)
          normal_user = create(:user)
          org.add_member(suspended_user)
          org.add_member(normal_user)


          suspended_user_seat_assignment = create(:copilot_seat_assignment, :user, assignable: suspended_user, organization: org)
          suspended_user_seat_assignment.convert_to_seats
          create(:copilot_seat, assigned_user: normal_user, organization: org)

          suspended_user.update_column(:suspended_at, Time.current)

          suspended_user_seat = Copilot::Seat.find_by(assigned_user_id: suspended_user.id)

          assert_equal 2, Copilot::Seat.count # includes org admin

          logs = capture_logs do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::SuspendedUserSeatsJob.perform_now
            end
          end

          assert_equal 1, Copilot::Seat.count
          assert_includes logs, "Running SuspendedUserSeatsJob"
          assert_includes logs, "Processing seat for suspended user"
          assert_includes logs, "gh.copilot.seat.id=\"#{suspended_user_seat&.id}"
          assert_includes logs, "gh.copilot.seat_assignment.owner.id=\"#{org.id}"
          assert_includes logs, "gh.copilot.seat_assignment.owner_type=\"Organization"
          assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"User"
          assert_nil Copilot::Seat.find_by(id: suspended_user.id)
          assert_nil Copilot::SeatAssignment.find_by(id: suspended_user_seat_assignment.id) # seat assignment also gets destroyed
          assert_dogstats_increment(1, "copilot.seat_management.suspended_user_seats_job.suspended_user_seat_destroyed")
        end
      end
    end

    context "with :copilot_revokable_access flag enabled" do
      test "sets access revoked for suspended user's seat assignment" do
        enable_feature_flag(:copilot_revokable_access)
        enable_feature_flag(:suspended_user_seats_job)
        freeze_time do
          org = create(:copilot_for_business_enabled_organization)
          suspended_user = create(:user)
          normal_user = create(:user)
          org.add_member(suspended_user)
          org.add_member(normal_user)


          suspended_user_seat_assignment = create(:copilot_seat_assignment, :user, assignable: suspended_user, organization: org)
          suspended_user_seat_assignment.convert_to_seats
          create(:copilot_seat, assigned_user: normal_user, organization: org)

          suspended_user.update_column(:suspended_at, Time.current)

          suspended_user_seat = T.must(Copilot::Seat.find_by(assigned_user_id: suspended_user.id))

          assert_equal 2, Copilot::Seat.count # includes org admin

          logs = capture_logs do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::SuspendedUserSeatsJob.perform_now
            end
          end

          assert_nothing_raised do
            suspended_user_seat.reload
            refute_nil suspended_user_seat.seat_assignment&.access_revoked_at
            refute_nil suspended_user_seat.seat_assignment&.pending_cancellation_date
          end
          assert_dogstats_increment(1, "copilot.seat_management.suspended_user_seats_job.access_revoked")
          assert_dogstats_increment(1, "copilot.seat_assignment.access_revoked")
          refute_dogstats_increment("copilot.seat_management.suspended_user_seats_job.suspended_user_seat_destroyed")
          assert_includes logs, "Running SuspendedUserSeatsJob"
          assert_includes logs, "Revoking access to Copilot: user_suspended"
          assert_includes logs, "Unassigning and revoking access to User seat assignment"
        end
      end

      test "sets access revoked for suspended user's team seat assignment" do
        enable_feature_flag(:copilot_revokable_access)
        enable_feature_flag(:suspended_user_seats_job)
        freeze_time do
          org = create(:copilot_for_business_enabled_organization)
          suspended_user = create(:user)
          normal_user = create(:user)
          org.add_member(suspended_user)
          org.add_member(normal_user)

          team = create(:team, organization: org)
          team.add_member(suspended_user)
          team.add_member(normal_user)

          team_seat_assignment = create(:copilot_seat_assignment, assignable: team, organization: org)
          team_seat_assignment.convert_to_seats

          suspended_user.update_column(:suspended_at, Time.current)

          suspended_user_seat = T.must(Copilot::Seat.includes(:seat_assignment).find_by(assigned_user_id: suspended_user.id))

          assert_equal 2, Copilot::Seat.count # includes org admin

          logs = capture_logs do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::SuspendedUserSeatsJob.perform_now
            end
          end

          disassociated_seat_assignment = Copilot::SeatAssignment.find_by(assignable: suspended_user.id)
          refute_nil disassociated_seat_assignment&.access_revoked_at
          refute_nil disassociated_seat_assignment&.pending_cancellation_date
          assert_dogstats_increment(1, "copilot.seat_management.suspended_user_seats_job.disassociated_seat_assignment")
          assert_dogstats_increment(1, "copilot.seat_management.suspended_user_seats_job.access_revoked")
          refute_dogstats_increment("copilot.seat_management.suspended_user_seats_job.suspended_user_seat_destroyed")
          assert_includes logs, "Created User SeatAssignment to disassociate from #{suspended_user_seat.seat_assignment&.assignable_type}"
          assert_includes logs, "gh.copilot.seat_assignment.id=\"#{disassociated_seat_assignment&.id}"
          assert_includes logs, "Revoking access to Copilot: user_suspended"
          suspended_user_seat.reload
          assert_equal disassociated_seat_assignment&.id, suspended_user_seat.seat_assignment&.id
        end
      end

      test "it does not reprocess seat assignment that has already been revoked" do
        enable_feature_flag(:copilot_revokable_access)
        enable_feature_flag(:suspended_user_seats_job)
        freeze_time do
          org = create(:copilot_for_business_enabled_organization)
          suspended_user = create(:user)
          normal_user = create(:user)
          org.add_member(suspended_user)
          org.add_member(normal_user)


          suspended_user_seat_assignment = create(:copilot_seat_assignment, :user, assignable: suspended_user, organization: org)
          suspended_user_seat_assignment.convert_to_seats
          create(:copilot_seat, assigned_user: normal_user, organization: org)

          suspended_user.update_column(:suspended_at, Time.current)

          logs = capture_logs do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::SuspendedUserSeatsJob.perform_now
              Copilot::SeatManagement::SuspendedUserSeatsJob.perform_now
            end
          end

          assert_dogstats_increment(1, "copilot.seat_assignment.access_revoked")
          assert_includes logs, "Seat assignment access already revoked"
          assert_equal 1, Copilot::SeatAssignment.where(assignable_id: suspended_user.id).count
        end
      end
    end

    context "with :suspended_user_seats_job flag disabled" do
      test "it does nothing when the :suspended_user_seats_job flag is disabled" do
        enable_feature_flag(:copilot_revokable_access)
        disable_feature_flag(:suspended_user_seats_job)
        freeze_time do
          org = create(:copilot_for_business_enabled_organization)
          suspended_user = create(:user)
          normal_user = create(:user)
          org.add_member(suspended_user)
          org.add_member(normal_user)

          team = create(:team, organization: org)
          team.add_member(suspended_user)
          team.add_member(normal_user)

          team_seat_assignment = create(:copilot_seat_assignment, assignable: team, organization: org)
          team_seat_assignment.convert_to_seats

          suspended_user.update_column(:suspended_at, Time.current)

          suspended_user_seat = T.must(Copilot::Seat.includes(:seat_assignment).find_by(assigned_user_id: suspended_user.id))
          original_seat_assignment_id = suspended_user_seat.seat_assignment&.id

          assert_equal 2, Copilot::Seat.count # includes org admin

          logs = capture_logs do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::SuspendedUserSeatsJob.perform_now
            end
          end

          disassociated_seat_assignment = Copilot::SeatAssignment.find_by(assignable: suspended_user.id)
          assert_nil disassociated_seat_assignment
          refute_dogstats_increment("copilot.seat_management.suspended_user_seats_job.disassociated_seat_assignment")
          refute_dogstats_increment("copilot.seat_management.suspended_user_seats_job.access_revoked")
          refute_dogstats_increment("copilot.seat_management.suspended_user_seats_job.suspended_user_seat_destroyed")
          refute_includes logs, "Disassociated seat from seat assignment for suspended user"
          refute_includes logs, "gh.copilot.seat_assignment.original_id=\"#{original_seat_assignment_id}"
          refute_includes logs, "gh.copilot.seat_assignment.new_id=\"#{disassociated_seat_assignment&.id}"
          refute_dogstats_increment("copilot.seat_assignment.access_revoked")
          refute_includes logs, "Revoking access to Copilot: suspended_user"
        end
      end
    end
  end
end
