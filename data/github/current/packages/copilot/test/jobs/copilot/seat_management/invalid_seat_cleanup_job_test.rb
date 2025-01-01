# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::SeatManagement::InvalidSeatCleanupJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  include DogstatsTestHelpers

  context "perform" do
    test "it will do nothing if there is nothing to do" do
      GitHub.flipper[:copilot_seat_assignment_job].enable
      # No seats
      assert_no_changes -> { Copilot::SeatAssignment.count + Copilot::Seat.count } do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::InvalidSeatCleanupJob.perform_now
        end
      end

      # Org seats
      org_seat_assignment = create(:copilot_seat_assignment, :organization)
      org_seat_assignment.convert_to_seats

      assert_no_changes -> { Copilot::SeatAssignment.count + Copilot::Seat.count } do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::InvalidSeatCleanupJob.perform_now
        end
      end

      # Business seats
      business_seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      business_seat_assignment.convert_to_seats

      assert_no_changes -> { Copilot::SeatAssignment.count + Copilot::Seat.count } do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::InvalidSeatCleanupJob.perform_now
        end
      end
    end

    test "it will remove seat assignments with an invalid org id" do
      freeze_time do
        GitHub.flipper[:copilot_seat_assignment_job].enable
        org_seat_assignment_1 = create(:copilot_seat_assignment, :organization)
        org_seat_assignment_2 = create(:copilot_seat_assignment, :organization)
        org_seat_assignment_1.convert_to_seats
        org_seat_assignment_2.convert_to_seats

        assert_equal 2, Copilot::SeatAssignment.count

        ::Organization.find(org_seat_assignment_1.owner_id).destroy!

        assert_equal 2, Copilot::SeatAssignment.count

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::InvalidSeatCleanupJob.perform_now
          end
        end

        assert_equal 1, Copilot::SeatAssignment.count

        assert_includes logs, "SeatAssignment owner ids without a corresponding owner"
        assert_includes logs, "gh.copilot.seat_assignment.invalid_org_count=\"1"
        assert_includes logs, "gh.copilot.seat_assignment.invalid_business_count=\"0"
        assert_includes logs, "Destroying SeatAssignment"
        assert_includes logs, "gh.copilot.seat_assignment.id=\"#{org_seat_assignment_1.id}"
        assert_dogstats_increment(1, "copilot.seat_management.invalid_seat_cleanup_job.seat_assignment_destroyed")
      end
    end

    test "it will remove seat assignments with an invalid business id" do
      freeze_time do
        GitHub.flipper[:copilot_seat_assignment_job].enable
        business_seat_assignment_1 = create(:copilot_seat_assignment, :enterprise_team)
        business_seat_assignment_2 = create(:copilot_seat_assignment, :enterprise_team)
        business_seat_assignment_1.convert_to_seats
        business_seat_assignment_2.convert_to_seats

        assert_equal 2, Copilot::SeatAssignment.count

        ::Business.find(business_seat_assignment_1.owner_id).destroy!

        assert_equal 2, Copilot::SeatAssignment.count

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::InvalidSeatCleanupJob.perform_now
          end
        end

        assert_equal 1, Copilot::SeatAssignment.count

        assert_includes logs, "SeatAssignment owner ids without a corresponding owner"
        assert_includes logs, "gh.copilot.seat_assignment.invalid_org_count=\"0"
        assert_includes logs, "gh.copilot.seat_assignment.invalid_business_count=\"1"
        assert_includes logs, "Destroying SeatAssignment"
        assert_includes logs, "gh.copilot.seat_assignment.id=\"#{business_seat_assignment_1.id}"
        assert_dogstats_increment(1, "copilot.seat_management.invalid_seat_cleanup_job.seat_assignment_destroyed")
      end
    end

    test "it will remove seat assignments with any invalid owner ids" do
      freeze_time do
        GitHub.flipper[:copilot_seat_assignment_job].enable
        org_seat_assignment_1 = create(:copilot_seat_assignment, :organization)
        org_seat_assignment_2 = create(:copilot_seat_assignment, :organization)
        org_seat_assignment_1.convert_to_seats
        org_seat_assignment_2.convert_to_seats
        business_seat_assignment_1 = create(:copilot_seat_assignment, :enterprise_team)
        business_seat_assignment_2 = create(:copilot_seat_assignment, :enterprise_team)
        business_seat_assignment_1.convert_to_seats
        business_seat_assignment_2.convert_to_seats

        assert_equal 4, Copilot::SeatAssignment.count

        ::Organization.find(org_seat_assignment_1.owner_id).destroy!
        ::Business.find(business_seat_assignment_1.owner_id).destroy!

        assert_equal 4, Copilot::SeatAssignment.count

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::InvalidSeatCleanupJob.perform_now
          end
        end

        assert_equal 2, Copilot::SeatAssignment.count

        assert_includes logs, "SeatAssignment owner ids without a corresponding owner"
        assert_includes logs, "gh.copilot.seat_assignment.invalid_org_count=\"1"
        assert_includes logs, "gh.copilot.seat_assignment.invalid_business_count=\"1"
        assert_includes logs, "Destroying SeatAssignment"
        assert_includes logs, "gh.copilot.seat_assignment.id=\"#{org_seat_assignment_1.id}"
        assert_includes logs, "gh.copilot.seat_assignment.id=\"#{business_seat_assignment_1.id}"
        assert_dogstats_increment(2, "copilot.seat_management.invalid_seat_cleanup_job.seat_assignment_destroyed")
      end
    end

    test "it will remove seat assignments with any invalid owner ids when they are pending cancellation" do
      freeze_time do
        GitHub.flipper[:copilot_seat_assignment_job].enable
        org_seat_assignment_1 = create(:copilot_seat_assignment, :organization)
        org_seat_assignment_2 = create(:copilot_seat_assignment, :organization)
        org_seat_assignment_1.convert_to_seats
        org_seat_assignment_2.convert_to_seats
        business_seat_assignment_1 = create(:copilot_seat_assignment, :enterprise_team)
        business_seat_assignment_2 = create(:copilot_seat_assignment, :enterprise_team)
        business_seat_assignment_1.convert_to_seats
        business_seat_assignment_2.convert_to_seats

        business_seat_assignment_1.update_column(:pending_cancellation_date, Time.current)
        business_seat_assignment_2.update_column(:pending_cancellation_date, Time.current)

        assert business_seat_assignment_1.pending_cancellation?
        assert business_seat_assignment_2.pending_cancellation?

        assert_equal 4, Copilot::SeatAssignment.count

        ::Organization.find(org_seat_assignment_1.owner_id).destroy!
        ::Business.find(business_seat_assignment_1.owner_id).destroy!

        assert_equal 4, Copilot::SeatAssignment.count

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::InvalidSeatCleanupJob.perform_now
          end
        end

        assert_equal 2, Copilot::SeatAssignment.count

        assert_includes logs, "SeatAssignment owner ids without a corresponding owner"
        assert_includes logs, "gh.copilot.seat_assignment.invalid_org_count=\"1"
        assert_includes logs, "gh.copilot.seat_assignment.invalid_business_count=\"1"
        assert_includes logs, "Destroying SeatAssignment"
        assert_includes logs, "gh.copilot.seat_assignment.id=\"#{org_seat_assignment_1.id}"
        assert_includes logs, "gh.copilot.seat_assignment.id=\"#{business_seat_assignment_1.id}"
        assert_dogstats_increment(2, "copilot.seat_management.invalid_seat_cleanup_job.seat_assignment_destroyed")
      end
    end

    test "it does nothing for suspended user seats with the clean_up_suspended_user_seats flag off" do
      GitHub.flipper[:clean_up_suspended_user_seats].disable

      freeze_time do
        GitHub.flipper[:copilot_seat_assignment_job].enable
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
            Copilot::SeatManagement::InvalidSeatCleanupJob.perform_now
          end
        end

        assert_equal 3, Copilot::Seat.count

        refute_includes logs, "SeatAssignment owner ids without a corresponding owner"
        refute_includes logs, "Cleaning up seats for suspended users"
        refute_includes logs, "gh.copilot.seat_assignment.invalid_org_count=\"0"
        refute_includes logs, "gh.copilot.seat_assignment.invalid_business_count=\"0"
        refute_includes logs, "Canceling seat for suspended user"
        refute_includes logs, "gh.copilot.seat.id=\"#{suspended_user_seat&.id}"
        refute_includes logs, "gh.copilot.seat_assignment.owner.id=\"#{org.id}"
        refute_includes logs, "gh.copilot.seat_assignment.owner_type=\"Organization"
        refute_includes logs, "gh.copilot.seat_assignment.assignable_type=\"Organization"
        refute_nil Copilot::Seat.find_by(assigned_user_id: suspended_user.id)
        refute_nil Copilot::SeatAssignment.find_by(id: org_seat_assignment.id)
      end
    end

    context "with :clean_up_suspended_user_seats flag on" do
      test "it will cancel seats for suspended users who are part of an org with a seat assignment" do
        GitHub.flipper[:clean_up_suspended_user_seats].enable
        freeze_time do
          GitHub.flipper[:copilot_seat_assignment_job].enable
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
              Copilot::SeatManagement::InvalidSeatCleanupJob.perform_now
            end
          end

          assert_equal 2, Copilot::Seat.count

          refute_includes logs, "SeatAssignment owner ids without a corresponding owner"
          refute_includes logs, "gh.copilot.seat_assignment.invalid_org_count=\"0"
          refute_includes logs, "gh.copilot.seat_assignment.invalid_business_count=\"0"
          assert_includes logs, "Canceling seat for suspended user"
          assert_includes logs, "gh.copilot.seat.id=\"#{suspended_user_seat&.id}"
          assert_includes logs, "gh.copilot.seat_assignment.owner.id=\"#{org.id}"
          assert_includes logs, "gh.copilot.seat_assignment.owner_type=\"Organization"
          assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"Organization"
          assert_nil Copilot::Seat.find_by(assigned_user_id: suspended_user.id)
          refute_nil Copilot::SeatAssignment.find_by(id: org_seat_assignment.id)
          assert_dogstats_increment(1, "copilot.seat_management.invalid_seat_cleanup_job.suspended_user_seat_destroyed")
        end
      end

      test "it will cancel seats for suspended users who are part of a team with a seat assignment" do
        GitHub.flipper[:clean_up_suspended_user_seats].enable
        freeze_time do
          GitHub.flipper[:copilot_seat_assignment_job].enable
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
              Copilot::SeatManagement::InvalidSeatCleanupJob.perform_now
            end
          end

          assert_equal 1, Copilot::Seat.count

          refute_includes logs, "SeatAssignment owner ids without a corresponding owner"
          refute_includes logs, "gh.copilot.seat_assignment.invalid_org_count=\"0"
          refute_includes logs, "gh.copilot.seat_assignment.invalid_business_count=\"0"
          assert_includes logs, "Canceling seat for suspended user"
          assert_includes logs, "gh.copilot.seat.id=\"#{suspended_user_seat&.id}"
          assert_includes logs, "gh.copilot.seat_assignment.owner.id=\"#{org.id}"
          assert_includes logs, "gh.copilot.seat_assignment.owner_type=\"Organization"
          assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"Team"
          assert_nil Copilot::Seat.find_by(id: suspended_user.id)
          refute_nil Copilot::SeatAssignment.find_by(id: team_seat_assignment.id)
          assert_dogstats_increment(1, "copilot.seat_management.invalid_seat_cleanup_job.suspended_user_seat_destroyed")
        end
      end

      test "it will cancel seats for suspended users with User seat assignments" do
        GitHub.flipper[:clean_up_suspended_user_seats].enable
        freeze_time do
          GitHub.flipper[:copilot_seat_assignment_job].enable
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
              Copilot::SeatManagement::InvalidSeatCleanupJob.perform_now
            end
          end

          assert_equal 1, Copilot::Seat.count

          refute_includes logs, "SeatAssignment owner ids without a corresponding owner"
          refute_includes logs, "gh.copilot.seat_assignment.invalid_org_count=\"0"
          refute_includes logs, "gh.copilot.seat_assignment.invalid_business_count=\"0"
          assert_includes logs, "Canceling seat for suspended user"
          assert_includes logs, "gh.copilot.seat.id=\"#{suspended_user_seat&.id}"
          assert_includes logs, "gh.copilot.seat_assignment.owner.id=\"#{org.id}"
          assert_includes logs, "gh.copilot.seat_assignment.owner_type=\"Organization"
          assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"User"
          assert_nil Copilot::Seat.find_by(id: suspended_user.id)
          assert_nil Copilot::SeatAssignment.find_by(id: suspended_user_seat_assignment.id) # seat assignment also gets destroyed
          assert_dogstats_increment(1, "copilot.seat_management.invalid_seat_cleanup_job.suspended_user_seat_destroyed")
        end
      end
    end
  end
end if GitHub.copilot_enabled?
