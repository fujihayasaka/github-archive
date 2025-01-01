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
  include DogstatsTestHelpers

  setup do
    enable_feature_flag(:copilot_seat_assignment_job)
  end

  # Check that we at least attempt to query the records, even if
  sig { params(user_id: Integer).void }
  def ensure_associated_records_removal_attempt(user_id)
    Copilot::Configuration.expects(:where).with(configurable_type: "User", configurable_id: user_id).returns(Copilot::Configuration.none).once
    Copilot::FreeUser.expects(:where).with(user_id: user_id).returns(Copilot::FreeUser.none).once
    Copilot::LimitedUser.expects(:where).with(user_id: user_id).returns(Copilot::LimitedUser.none).once
    Copilot::EditorNotification.expects(:where).with(user_id: user_id).returns(Copilot::EditorNotification.none).once
    Copilot::AggregateUsageDetail.expects(:where).with(user_id: user_id).returns(Copilot::AggregateUsageDetail.none).once
    Copilot::TechnicalPreviewUser.expects(:where).with(user_id: user_id).returns(Copilot::TechnicalPreviewUser.none).once
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


      refute_match "Loaded Copilot Seats for user", logs
      assert_match "No Copilot Seats Found for user", logs
      refute_match "Destroying Copilot Seats for user", logs
      assert_match "No User Level Copilot Seat Assignments for user", logs if !GitHub.flipper[:copilot_revokable_access].enabled?
      assert_match "No User Seat Assignments for user which were not linked to seats", logs if GitHub.flipper[:copilot_revokable_access].enabled?
      refute_match "Destroying associated Copilot records for user, if any exist", logs
      refute_dogstats_count("copilot.seat_management.user_job.seats_destroyed")
      refute_dogstats_count("copilot.seat_management.user_job.user_seat_assignments_destroyed")
      refute_dogstats_increment("copilot.seat_management.user_job.access_revoked") if GitHub.flipper[:copilot_revokable_access].enabled?
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

      refute_match "Loaded Copilot Seats for user", logs
      assert_match "No Copilot Seats Found for user", logs
      refute_match "Destroying Copilot Seats for user", logs
      assert_match "No User Level Copilot Seat Assignments for user", logs if !GitHub.flipper[:copilot_revokable_access].enabled?
      assert_match "No User Seat Assignments for user which were not linked to seats", logs if GitHub.flipper[:copilot_revokable_access].enabled?
      refute_match "Destroying associated Copilot records for user, if any exist", logs
      refute_dogstats_count("copilot.seat_management.user_job.seats_destroyed")
      refute_dogstats_count("copilot.seat_management.user_job.user_seat_assignments_destroyed")
      refute_dogstats_increment("copilot.seat_management.user_job.access_revoked") if GitHub.flipper[:copilot_revokable_access].enabled?
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
      assert_match "No Copilot Seats Found for user", logs
      refute_match "Destroying Copilot Seats for user", logs
      assert_match "No User Level Copilot Seat Assignments for user", logs if !GitHub.flipper[:copilot_revokable_access].enabled?
      assert_match "No User Seat Assignments for user which were not linked to seats", logs if GitHub.flipper[:copilot_revokable_access].enabled?
      refute_match "Destroying associated Copilot records for user, if any exist", logs
      refute_dogstats_count("copilot.seat_management.user_job.seats_destroyed")
      refute_dogstats_count("copilot.seat_management.user_job.user_seat_assignments_destroyed")
      refute_dogstats_increment("copilot.seat_management.user_job.access_revoked") if GitHub.flipper[:copilot_revokable_access].enabled?
    end

    context "with copilot_revokable_access disabled" do
      test "deletes seat assignment for user with no seats" do
        disable_feature_flag(:copilot_revokable_access)
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

        assert_match "No Copilot Seats Found for user", logs
        refute_match "Destroying Copilot Seats for user", logs
        assert_match "Destroying User Level Copilot Seat Assignments for user", logs
        refute_match "Destroying Copilot Seats for user", logs
        refute_match "Destroying associated Copilot records for user, if any exist", logs
        assert_dogstats_count(1, "copilot.seat_management.user_job.user_seat_assignments_destroyed")
      end

      test "deletes seat assignment and seat for user" do
        disable_feature_flag(:copilot_revokable_access)
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

        assert_match "Loaded Copilot Seats for user", logs
        assert_match "Destroying User Level Copilot Seat Assignments for user", logs
        assert_match "Destroying Copilot Seats for user", logs
        refute_match "Destroying associated Copilot records for user, if any exist", logs
        assert_dogstats_count(1, "copilot.seat_management.user_job.seats_destroyed")
        assert_dogstats_count(1, "copilot.seat_management.user_job.user_seat_assignments_destroyed")
      end
    end

    context "with copilot_revokable_access enabled" do
      test "reports error if a given seat has no seat assignment" do
        enable_feature_flag(:copilot_revokable_access)
        user = create(:user)
        organization = create(:organization)
        organization.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, owner: organization, assignable: user, assigning_user: organization.admins.first)
        seat_assignment.convert_to_seats
        seat = seat_assignment.seats.first
        seat_assignment.destroy

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::UserJob.any_instance.expects(:report_error).once.with("Seat assignment not found for seat #{seat.id}", anything)

            Copilot::SeatManagement::UserJob.perform_now(
              action: :destroy,
              transaction_id: "1234",
              payload: { foo: "bar" },
              user_id: user.id,
            )
          end
        end

        refute Copilot::SeatAssignment.exists?(seat_assignment.id)
        assert Copilot::Seat.exists?(seat.id)

        assert_match "Loaded Copilot Seats for user", logs
        refute_match "Destroying User Level Copilot Seat Assignments for user", logs
        refute_match "Destroying Copilot Seats for user", logs
        refute_match "Destroying associated Copilot records for user, if any exist", logs
        refute_dogstats_increment("copilot.seat_management.user_job.access_revoked")
      end

      test "unassigns and revokes access from existing seat assignments" do
        enable_feature_flag(:copilot_revokable_access)
        user = create(:user)
        organization = create(:organization)
        organization.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, owner: organization, assignable: user, assigning_user: organization.admins.first)
        seat_assignment.convert_to_seats
        seat = seat_assignment.seats.first

        Copilot::SeatManagement::UserJob.any_instance.expects(:report_error).never
        Copilot::SeatManagement::SeatAssignmentHelpers.expects(:create_disassociated_seat_assignment).never

        logs = capture_logs do
          assert_no_changes -> { Copilot::SeatAssignment.count } do
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
        assert Copilot::Seat.exists?(seat.id)

        assert seat_assignment.reload.access_revoked?

        assert_match "No User Seat Assignments for user which were not linked to seats", logs
        refute_match "Destroying associated Copilot records for user, if any exist", logs
        assert_dogstats_increment(1, "copilot.seat_management.user_job.access_revoked")
      end

      test "destroys random unassociated seat assignments " do
        enable_feature_flag(:copilot_revokable_access)
        user = create(:user)
        organization = create(:organization)
        organization2 = create(:organization)
        organization.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, owner: organization, assignable: user, assigning_user: organization.admins.first)

        seat_assignment.convert_to_seats
        seat = seat_assignment.seats.first

        # random other seat assignment in a different org with no seat associated
        random_assignment = create(:copilot_seat_assignment, owner: organization2, assignable: user, assigning_user: organization2.admins.first)

        Copilot::SeatManagement::UserJob.any_instance.expects(:report_error).never
        Copilot::SeatManagement::SeatAssignmentHelpers.expects(:create_disassociated_seat_assignment).never

        logs = capture_logs do
          assert_changes -> { Copilot::SeatAssignment.count }, -1 do
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
        refute Copilot::SeatAssignment.exists?(random_assignment.id)
        assert Copilot::Seat.exists?(seat.id)

        assert seat_assignment.reload.access_revoked?

        assert_match "Destroying User Seat Assignments for user which were not linked to seats", logs
        refute_match "Destroying associated Copilot records for user, if any exist", logs
        assert_dogstats_count(1, "copilot.seat_management.user_job.orphaned_assignments_destroyed")
      end

      test "creates disassociated seat assignment and unassigns and revokes access from it if the existing assignment is Team" do
        enable_feature_flag(:copilot_revokable_access)
        user = create(:user)
        organization = create(:organization)
        team = create(:team, organization: organization)

        team.add_member(create(:user))
        team.add_member(user)

        organization.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, owner: organization, assignable: team, assigning_user: organization.admins.first)
        seat_assignment.convert_to_seats
        seat = Copilot::Seat.for_user(user).first

        Copilot::SeatManagement::UserJob.any_instance.expects(:report_error).never

        logs = capture_logs do
          assert_changes -> { Copilot::SeatAssignment.count }, 1 do
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
        user_seat_assignment = Copilot::SeatAssignment.where(assignable: user).first
        assert user_seat_assignment&.reload.access_revoked?
        assert Copilot::Seat.exists?(seat&.id)
        assert_equal seat&.reload.seat_assignment, user_seat_assignment


        assert_match "No User Seat Assignments for user which were not linked to seats", logs
        assert_match "Unassigning and revoking access for disassociated seat assignment", logs
        refute_match "Destroying associated Copilot records for user, if any exist", logs
        assert_dogstats_increment(1, "copilot.seat_management.user_job.access_revoked")
        assert_dogstats_increment(1, "copilot.seat_management.user_job.assignment_disassociated")
      end
    end

    test "resolves tenant on a multi-tenant enterprise with business owner" do
      on_multi_tenant_enterprise do
        # Simulate no tenant being set
        GitHub::CurrentTenant.remove
        assert_nil GitHub::CurrentTenant.get

        user = create(:emu)

        Copilot::SeatManagement::UserJob.perform_now(
          action: :destroy,
          transaction_id: "1234",
          payload: { foo: "bar" },
          user_id: user.id,
        )

        refute_nil GitHub::CurrentTenant.get
        assert_equal user.enterprise_managed_business, GitHub::CurrentTenant.get
      end
    end

    test "attempts to destroy associated Copilot records when clean_records is true" do
      user = create(:user)

      ensure_associated_records_removal_attempt(user.id)

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::UserJob.perform_now(
            action: :destroy,
            transaction_id: "1234",
            payload: { foo: "bar" },
            user_id: user.id,
            clean_records: true
          )
        end
      end

      assert_match "Destroying associated Copilot records for user, if any exist", logs
    end
  end
end if GitHub.copilot_enabled?
