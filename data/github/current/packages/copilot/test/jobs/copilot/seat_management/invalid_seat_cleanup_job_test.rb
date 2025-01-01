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
      enable_feature_flag(:copilot_seat_assignment_job)
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
        enable_feature_flag(:copilot_seat_assignment_job)
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
        enable_feature_flag(:copilot_seat_assignment_job)
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
        enable_feature_flag(:copilot_seat_assignment_job)
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
        enable_feature_flag(:copilot_seat_assignment_job)
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
  end
end if GitHub.copilot_enabled?
