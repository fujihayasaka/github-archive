# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::SeatManagement::ExternalIdentityJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  include HydroTestHelpers
  include DogstatsTestHelpers

  setup do
    GitHub.flipper[:copilot_seat_assignment_job].enable
    GitHub.flipper[:copilot_external_identity_job].enable
    GitHub.flipper[:destroy_seats_for_deprovisioned_users].disable
  end

  context "perform" do
    test "doesn't do anything if the feature flag is disabled" do
      GitHub.flipper[:copilot_seat_assignment_job].disable
      GitHub.flipper[:copilot_external_identity_job].disable

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::ExternalIdentityJob.perform_now(
            user_id: 1,
            external_identity_id: 1,
            transaction_id: "1234",
            action: :provision,
            payload: {}
          )
        end
      end

      assert_includes logs, "Skipping Copilot::SeatManagement::ExternalIdentityJob"
    end

    test "requires both flags - copilot_seat_assignment_job" do
      GitHub.flipper[:copilot_seat_assignment_job].enable
      GitHub.flipper[:copilot_external_identity_job].disable

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::ExternalIdentityJob.perform_now(
            user_id: 1,
            external_identity_id: 1,
            transaction_id: "1234",
            action: :provision,
            payload: {}
          )
        end
      end

      assert_includes logs, "Skipping Copilot::SeatManagement::ExternalIdentityJob"
    end

    test "requires both flags - copilot_external_identity_job" do
      GitHub.flipper[:copilot_seat_assignment_job].disable
      GitHub.flipper[:copilot_external_identity_job].enable

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::ExternalIdentityJob.perform_now(
            user_id: 1,
            external_identity_id: 1,
            transaction_id: "1234",
            action: :provision,
            payload: {}
          )
        end
      end

      assert_includes logs, "Skipping Copilot::SeatManagement::ExternalIdentityJob"
    end

    test "raises an error if the action is invalid" do
      identity = create(:external_identity)
      user = identity.user

      assert_raises(ArgumentError) do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::ExternalIdentityJob.perform_now(
            user_id: user.id,
            external_identity_id: identity.id,
            transaction_id: "1234",
            action: :spoon,
            payload: { foo: "bar" },
          )
        end
      end
    end
  end

  context "deprovision" do
    test "does nothing without seats" do
      identity = create(:external_identity)
      user = identity.user

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::ExternalIdentityJob.perform_now(
            user_id: user.id,
            external_identity_id: identity.id,
            transaction_id: "1234",
            action: :deprovision,
            payload: { foo: "bar" },
          )
        end
      end
      assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
      assert_includes logs, "Deprovisioned user has no seats"
    end

    test "handles error and logs for seat with no seat assignment, skips the seat" do
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).never
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_cancelled).never
      Copilot::Seat.any_instance.expects(:send_email).never

      identity = create(:external_identity)
      organization = identity.target
      user = identity.user
      team = create(:team, organization: organization)
      team.add_member(user)
      seat_assignment = create(:copilot_seat_assignment, assignable: team, organization: organization)
      create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: user, organization: organization)

      seat_assignment.destroy!

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::ExternalIdentityJob.perform_now(
            user_id: user.id,
            external_identity_id: identity.id,
            transaction_id: "1234",
            action: :deprovision,
            payload: { foo: "bar" },
          )
        end
      end
      assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
      assert_includes logs, "Processing seat"
      assert_includes logs, "SeatAssignment not found for deprovisioned user's Seat, skipping it"
      refute_includes logs, "Deprovisioned user has no seats"
      assert_dogstats_increment(1, "copilot.external_identity_job.no_seat_assignment_for_seat")
      assert_dogstats_increment(0, "copilot.external_identity_job.team_seat_assignment")
    end

    context ":destroy_seats_for_deprovisioned_users flag disabled" do
      test "skips enterprise team level seat assignment" do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_cancelled).never

        seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
        seat_assignment.convert_to_seats

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::ExternalIdentityJob.perform_now(
              user_id: seat_assignment.seats.first.assigned_user.id,
              external_identity_id: 1234,
              transaction_id: "1234",
              action: :deprovision,
              payload: { foo: "bar" },
            )
          end
        end

        assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
        assert_includes logs, "Processing seat"
        assert_includes logs, "Skipping seat assignment for enterprise team"
      end

      test "handles team level seat assignment" do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).with(instance_of(Copilot::SeatAssignment), nil, :external_identity_deprovisioned).once
        identity = create(:external_identity)
        organization = identity.target
        user = identity.user
        team = create(:team, organization: organization)
        team.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, assignable: team, organization: organization)
        seat_assignment.convert_to_seats

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::ExternalIdentityJob.perform_now(
              user_id: user.id,
              external_identity_id: identity.id,
              transaction_id: "1234",
              action: :deprovision,
              payload: { foo: "bar" },
            )
          end
        end
        assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
        assert_includes logs, "Processing seat"
        assert_includes logs, "Creating new user seat assignment"
        assert_includes logs, "Disassociating seat from seat assignment"
        assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"TEAM\""
        refute_includes logs, "Queuing delayed_converter_job"
        assert_dogstats_increment(1, "copilot.external_identity_job.team_seat_assignment")

        user_seat_assignment = Copilot::SeatAssignment.where(assignable: user).first

        assert_hydro_published(
          {
            assignment: Hydro::EntitySerializer.copilot_seat_assignment(user_seat_assignment),
            owner_details: Hydro::EntitySerializer.copilot_owner_details(organization),
            actor: Hydro::EntitySerializer.user(nil),
            event_type: "team_member_deprovisioned_disassociate_seat",
            copilot_for_business_details: Hydro::EntitySerializer.copilot_for_business_details({ old_seat_assignment_id: seat_assignment.id }),
          },
          schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentCreated",
        )
      end

      test "handles organization level seat assignment" do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).once
        identity = create(:external_identity)
        organization = identity.target
        user = identity.user
        seat_assignment = create(:copilot_seat_assignment, assignable: organization, organization: organization)
        seat_assignment.convert_to_seats

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::ExternalIdentityJob.perform_now(
              user_id: user.id,
              external_identity_id: identity.id,
              transaction_id: "1234",
              action: :deprovision,
              payload: { foo: "bar" },
            )
          end
        end
        assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
        assert_includes logs, "Processing seat"
        assert_includes logs, "Creating new user seat assignment"
        assert_includes logs, "Disassociating seat from seat assignment"
        assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"ORGANIZATION\""
        refute_includes logs, "Queuing delayed_converter_job"
        assert_dogstats_increment(1, "copilot.external_identity_job.organization_seat_assignment")

        user_seat_assignment = Copilot::SeatAssignment.where(assignable: user).first

        assert_hydro_published(
          {
            assignment: Hydro::EntitySerializer.copilot_seat_assignment(user_seat_assignment),
            owner_details: Hydro::EntitySerializer.copilot_owner_details(organization),
            actor: Hydro::EntitySerializer.user(nil),
            event_type: "organization_member_deprovisioned_disassociate_seat",
            copilot_for_business_details: Hydro::EntitySerializer.copilot_for_business_details({ old_seat_assignment_id: seat_assignment.id }),
          },
          schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentCreated",
        )
      end

      test "handles user level seat assignment" do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never
        identity = create(:external_identity)
        organization = identity.target
        user = identity.user
        seat_assignment = create(:copilot_seat_assignment, assignable: user, organization: organization)
        seat_assignment.convert_to_seats

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).once.with(seat_assignment, nil, :external_identity_deprovisioned)

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::ExternalIdentityJob.perform_now(
              user_id: user.id,
              external_identity_id: identity.id,
              transaction_id: "1234",
              action: :deprovision,
              payload: { foo: "bar" },
            )
          end
        end

        assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
        assert_includes logs, "Processing seat"
        assert_includes logs, "Unassigning user seat assignment"
        assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"USER\""
        refute_includes logs, "Queuing delayed_converter_job"
        assert_dogstats_increment(1, "copilot.external_identity_job.user_seat_assignment")

        seat_assignment.reload
        refute_nil seat_assignment.pending_cancellation_date
      end

      test "handles user level seat assignment where the user does not match" do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).never
        Copilot::ErrorReporter.expects(:report!).once
        identity = create(:external_identity)
        organization = identity.target
        user = identity.user
        seat_assignment = create(:copilot_seat_assignment, assignable: user, organization: organization)
        seat_assignment.convert_to_seats

        other_user = create(:user)
        organization.add_member(other_user)
        seat_assignment.update!(assignable_id: other_user.id)

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::ExternalIdentityJob.perform_now(
              user_id: user.id,
              external_identity_id: identity.id,
              transaction_id: "1234",
              action: :deprovision,
              payload: { foo: "bar" },
            )
          end
        end
        assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
        assert_includes logs, "Processing seat"
        assert_includes logs, "Seat assignment pointing at wrong user"
        assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"USER\""
        refute_includes logs, "Queuing delayed_converter_job"
      end
    end

    context ":destroy_seats_for_deprovisioned_users flag enabled" do
      test "handles enterprise team level seat assignment with flag enabled" do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).never

        seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
        team_member = User.find(seat_assignment.assignable.member_user_ids.first)
        ent_seat = create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: team_member)

        GitHub.flipper[:copilot_external_identity_job].enable
        GitHub.flipper[:destroy_seats_for_deprovisioned_users].enable

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_cancelled).once.with(ent_seat, nil, false, :user_deprovisioned, trial_seat: false)

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::ExternalIdentityJob.perform_now(
              user_id: team_member.id,
              external_identity_id: 1234,
              transaction_id: "1234",
              action: :deprovision,
              payload: { foo: "bar" },
            )
          end
        end

        assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
        assert_includes logs, "Processing seat"
        assert_includes logs, "Canceling deprovisioned user's seat"
        assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"ENTERPRISE_TEAM\""
        refute_includes logs, "Deprovisioned user has no seats"
        assert_dogstats_increment(1, "copilot.external_identity_job.enterprise_team_seat_assignment")
      end

      test "handles team level seat assignment" do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).never

        identity = create(:external_identity)
        organization = identity.target
        GitHub.flipper[:destroy_seats_for_deprovisioned_users].enable(organization)
        user = identity.user
        team = create(:team, organization: organization)
        team.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, assignable: team, organization: organization)
        team_seat = create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: user, organization: organization)

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_cancelled).once.with(team_seat, nil, false, :user_deprovisioned, trial_seat: false)
        Copilot::Seat.any_instance.expects(:send_email).never

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::ExternalIdentityJob.perform_now(
              user_id: user.id,
              external_identity_id: identity.id,
              transaction_id: "1234",
              action: :deprovision,
              payload: { foo: "bar" },
            )
          end
        end
        assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
        assert_includes logs, "Processing seat"
        assert_includes logs, "Canceling deprovisioned user's seat"
        assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"TEAM\""
        refute_includes logs, "Deprovisioned user has no seats"
        assert_dogstats_increment(1, "copilot.external_identity_job.team_seat_assignment")
      end

      test "handles organization level seat assignment" do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).never
        identity = create(:external_identity)
        organization = identity.target
        GitHub.flipper[:destroy_seats_for_deprovisioned_users].enable(organization)
        user = identity.user
        seat_assignment = create(:copilot_seat_assignment, assignable: organization, organization: organization)

        org_seat = create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: user, organization: organization)

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_cancelled).once.with(org_seat, nil, false, :user_deprovisioned, trial_seat: false)
        Copilot::Seat.any_instance.expects(:send_email).never

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::ExternalIdentityJob.perform_now(
              user_id: user.id,
              external_identity_id: identity.id,
              transaction_id: "1234",
              action: :deprovision,
              payload: { foo: "bar" },
            )
          end
        end
        assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
        assert_includes logs, "Processing seat"
        assert_includes logs, "Canceling deprovisioned user's seat"
        assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"ORGANIZATION\""
        refute_includes logs, "Deprovisioned user has no seats"
        assert_dogstats_increment(1, "copilot.external_identity_job.organization_seat_assignment")
      end

      test "handles user level seat assignment" do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).never

        identity = create(:external_identity)
        organization = identity.target
        GitHub.flipper[:destroy_seats_for_deprovisioned_users].enable(organization)
        user = identity.user
        seat_assignment = create(:copilot_seat_assignment, assignable: user, organization: organization)
        user_seat = create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: user, organization: organization)

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_cancelled).once.with(user_seat, nil, false, :user_deprovisioned, trial_seat: false)
        Copilot::Seat.any_instance.expects(:send_email).never

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::ExternalIdentityJob.perform_now(
              user_id: user.id,
              external_identity_id: identity.id,
              transaction_id: "1234",
              action: :deprovision,
              payload: { foo: "bar" },
            )
          end
        end

        assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
        assert_includes logs, "Processing seat"
        assert_includes logs, "Canceling deprovisioned user's seat"
        assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"USER\""
        assert_dogstats_increment(1, "copilot.external_identity_job.user_seat_assignment")

        assert_empty Copilot::Seat.where(id: user_seat.id)
      end

      test "handles user level seat assignment where the user does not match" do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_cancelled).never
        Copilot::Seat.any_instance.expects(:send_email).never
        Copilot::ErrorReporter.expects(:report!).once

        identity = create(:external_identity)
        organization = identity.target
        GitHub.flipper[:destroy_seats_for_deprovisioned_users].enable(organization)
        user = identity.user
        seat_assignment = create(:copilot_seat_assignment, assignable: user, organization: organization)
        create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: user, organization: organization)

        other_user = create(:user)
        organization.add_member(other_user)
        seat_assignment.update!(assignable_id: other_user.id)

        logs = capture_logs do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::ExternalIdentityJob.perform_now(
              user_id: user.id,
              external_identity_id: identity.id,
              transaction_id: "1234",
              action: :deprovision,
              payload: { foo: "bar" },
            )
          end
        end
        assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
        assert_includes logs, "Processing seat"
        assert_includes logs, "Seat Assignment for deprovisioned user is pointing at wrong user"
        assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"USER\""
        refute_includes logs, "Queuing delayed_converter_job"
      end
    end
  end

  context "provision" do
    test "does nothing without assignments" do
      identity = create(:external_identity)
      user = identity.user

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::ExternalIdentityJob.perform_now(
            user_id: user.id,
            external_identity_id: identity.id,
            transaction_id: "1234",
            action: :provision,
            payload: { foo: "bar" },
          )
        end
      end
      assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
      assert_includes logs, "User's organizations have no org level seat assignments"
      assert_includes logs, "User's teams have no team level seat assignments"
      assert_includes logs, "User has no user level seat assignments"
    end

    test "provisions with an org level assignment" do
      identity = create(:external_identity)
      organization = identity.target
      user = identity.user
      assignment = create(:copilot_seat_assignment, assignable: organization, organization: organization)
      assert_equal 0, assignment.seats.count

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::ExternalIdentityJob.perform_now(
            user_id: user.id,
            external_identity_id: identity.id,
            transaction_id: "1234",
            action: :provision,
            payload: { foo: "bar" },
          )
        end
      end
      assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
      assert_includes logs, "User's organizations have org levels seat assignments"
      assert_includes logs, "User's teams have no team level seat assignments"
      assert_includes logs, "User has no user level seat assignments"

      assignment.reload
      assert_equal organization.member_ids.count, assignment.seats.count
    end

    test "provisions with an team level assignment" do
      identity = create(:external_identity)
      organization = identity.target
      user = identity.user
      team = create(:team, organization: organization)
      team.add_member(user)
      assignment = create(:copilot_seat_assignment, assignable: team, organization: organization)
      assert_equal 0, assignment.seats.count

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::ExternalIdentityJob.perform_now(
            user_id: user.id,
            external_identity_id: identity.id,
            transaction_id: "1234",
            action: :provision,
            payload: { foo: "bar" },
          )
        end
      end
      assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
      assert_includes logs, "User's organizations have no org level seat assignments"
      assert_includes logs, "User's teams have team level seat assignments"
      assert_includes logs, "User has no user level seat assignments"

      assignment.reload
      assert_equal team.member_ids.count, assignment.seats.count
    end

    test "provisions with a user level assignment" do
      identity = create(:external_identity)
      user = identity.user
      organization = identity.target
      assignment = create(:copilot_seat_assignment, assignable: user, organization: organization)
      assert_equal 0, assignment.seats.count

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::ExternalIdentityJob.perform_now(
            user_id: user.id,
            external_identity_id: identity.id,
            transaction_id: "1234",
            action: :provision,
            payload: { foo: "bar" },
          )
        end
      end
      assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
      assert_includes logs, "User's organizations have no org level seat assignments"
      assert_includes logs, "User's teams have no team level seat assignments"
      assert_includes logs, "User has user level seat assignments"

      assignment.reload
      assert_equal 1, assignment.seats.count
    end
  end
end if GitHub.copilot_enabled?
