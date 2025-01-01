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
    enable_feature_flag(:copilot_seat_assignment_job)
    enable_feature_flag(:copilot_external_identity_job)
    enable_feature_flag(:copilot_external_identity_job_handle_deprovision)
    enable_feature_flag(:copilot_external_identity_job_handle_provision)
    disable_feature_flag(:destroy_seats_for_deprovisioned_users)
    disable_feature_flag(:copilot_revokable_access)
  end

  context "perform" do
    test "doesn't do anything if the job feature flag is disabled" do
      disable_feature_flag(:copilot_seat_assignment_job)
      disable_feature_flag(:copilot_external_identity_job)

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
      enable_feature_flag(:copilot_seat_assignment_job)
      disable_feature_flag(:copilot_external_identity_job)

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
      disable_feature_flag(:copilot_seat_assignment_job)
      enable_feature_flag(:copilot_external_identity_job)

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
    test "does nothing if feature flag is disabled" do
      disable_feature_flag(:copilot_external_identity_job_handle_deprovision)

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
      refute_includes logs, "Deprovisioned user has no seats"
    end

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
      assert_includes logs, "Processing Copilot seats and seat assignments for deprovisioned user."
      assert_includes logs, "SeatAssignment not found for deprovisioned user's Seat, skipping it"
      refute_includes logs, "Deprovisioned user has no seats"
      assert_dogstats_increment(1, "copilot.external_identity_job.no_seat_assignment_for_seat")
      refute_dogstats_increment("copilot.external_identity_job.seat_processed_for_deprovisioned", tags: ["type:team"])
    end

    context ":destroy_seats_for_deprovisioned_users flag disabled" do
      context "with copilot_revokable_access flag enabled" do
        test "revokes access for disassociated user assignment from a team" do
          enable_feature_flag(:copilot_revokable_access)

          identity = create(:external_identity)
          organization = identity.target
          user = identity.user
          team = create(:team, organization: organization)
          team.add_member(user)
          seat_assignment = create(:copilot_seat_assignment, assignable: team, organization: organization)
          seat_assignment.convert_to_seats

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned)
            .with(instance_of(Copilot::SeatAssignment), nil, :external_identity_deprovisioned)
            .once
          Copilot::Instrumenter.expects(:instrument_copilot_user_access_revoked).once

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

          assert_includes logs, "Revoking access to Copilot: external_identity_deprovisioned"
          assert_dogstats_increment(1, "copilot.external_identity_job.seat_processed_for_deprovisioned", tags: ["type:team"])
        end

        test "revokes access for user assignment diassociated from organization" do
          enable_feature_flag(:copilot_revokable_access)

          identity = create(:external_identity)
          organization = identity.target
          user = identity.user

          seat_assignment = create(:copilot_seat_assignment, assignable: organization, owner: organization, assigning_user: organization.admins.first)
          seat_assignment.convert_to_seats

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned)
            .with(instance_of(Copilot::SeatAssignment), nil, :external_identity_deprovisioned)
            .once
          Copilot::Instrumenter.expects(:instrument_copilot_user_access_revoked).once

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

          assert_includes logs, "Revoking access to Copilot: external_identity_deprovisioned"
          assert_dogstats_increment(1, "copilot.external_identity_job.seat_processed_for_deprovisioned", tags: ["type:organization"])
        end

        test "revokes access for user assignment" do
          enable_feature_flag(:copilot_revokable_access)

          identity = create(:external_identity)
          organization = identity.target
          user = identity.user

          seat_assignment = create(:copilot_seat_assignment, assignable: user, owner: organization, assigning_user: organization.admins.first)
          seat_assignment.convert_to_seats

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned)
            .with(instance_of(Copilot::SeatAssignment), nil, :external_identity_deprovisioned)
            .once
          Copilot::Instrumenter.expects(:instrument_copilot_user_access_revoked).once

          logs = capture_logs do
            assert_no_changes -> { Copilot::SeatAssignment.count } do
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
          end

          assert_includes logs, "Revoking access to Copilot: external_identity_deprovisioned"
          assert_dogstats_increment(1, "copilot.external_identity_job.seat_processed_for_deprovisioned", tags: ["type:user"])
        end
      end

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
        assert_includes logs, "Processing Copilot seats and seat assignments for deprovisioned user."
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
        assert_includes logs, "Processing Copilot seats and seat assignments for deprovisioned user."
        assert_includes logs, "Creating new user seat assignment"
        assert_includes logs, "Disassociating seat from seat assignment"
        assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"TEAM\""
        refute_includes logs, "Queuing delayed_converter_job"
        assert_dogstats_increment(1, "copilot.external_identity_job.seat_processed_for_deprovisioned", tags: ["type:team"])

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
        assert_includes logs, "Processing Copilot seats and seat assignments for deprovisioned user."
        assert_includes logs, "Creating new user seat assignment"
        assert_includes logs, "Disassociating seat from seat assignment"
        assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"ORGANIZATION\""
        refute_includes logs, "Queuing delayed_converter_job"
        assert_dogstats_increment(1, "copilot.external_identity_job.seat_processed_for_deprovisioned", tags: ["type:organization"])

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
        assert_includes logs, "Processing Copilot seats and seat assignments for deprovisioned user."
        assert_includes logs, "Unassigning user seat assignment"
        assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"USER\""
        refute_includes logs, "Queuing delayed_converter_job"
        assert_dogstats_increment(1, "copilot.external_identity_job.seat_processed_for_deprovisioned", tags: ["type:user"])

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
        assert_includes logs, "Processing Copilot seats and seat assignments for deprovisioned user."
        assert_includes logs, "Seat Assignment for deprovisioned user is pointing at wrong user"
        assert_includes logs, "gh.copilot.seat_assignment.assignable_type=\"USER\""
        refute_includes logs, "Queuing delayed_converter_job"
      end
    end
  end

  context "provision" do
    test "does nothing if feature flag is disabled" do
      disable_feature_flag(:copilot_external_identity_job_handle_provision)

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
      refute_includes logs, "Processing Copilot seat assignments for provisioned user"
    end

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
      assert_includes logs, "Processing Organization seat assignment for provisioned user"
      assert_includes logs, "User's teams have no team level seat assignments"
      assert_includes logs, "User has no user level seat assignments"

      assignment.reload

      # we only have one seat, because we only inserted the seat for the provisioned user
      # and haven't explicitly created a seat for the admin in this test
      assert_equal 1, assignment.seats.count
      assert_dogstats_increment(1, "copilot.external_identity_job.seat_inserted", tags: ["type:organization"])
    end

    test "provisions with a team level assignment, only creates 1 seat if the user is on multiple teams" do
      identity = create(:external_identity)
      organization = identity.target
      user = identity.user
      team1 = create(:team, organization: organization)
      team1.add_member(user)

      team2 = create(:team, organization: organization)
      team2.add_member(user)

      assignment1 = create(:copilot_seat_assignment, assignable: team1, organization: organization)
      assignment2 = create(:copilot_seat_assignment, assignable: team2, organization: organization)
      assert_equal 0, assignment1.seats.count

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
      assert_includes logs, "Processing Team seat assignment for provisioned user"
      assert_includes logs, "User already has a seat for this organization"
      assert_includes logs, "User has no user level seat assignments"

      assignment1.reload
      assignment2.reload
      assert_equal 1, Copilot::Seat.count
      assert_dogstats_increment(1, "copilot.external_identity_job.seat_inserted", tags: ["type:team"])
    end

    test "provisions with a user level assignment" do
      identity = create(:external_identity)
      user = identity.user
      organization = identity.target
      actor = organization.admins.first
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
            actor_id: actor.id,
          )
        end
      end
      assert_includes logs, "Performing Copilot::SeatManagement::ExternalIdentityJob"
      assert_includes logs, "User's organizations have no org level seat assignments"
      assert_includes logs, "User's teams have no team level seat assignments"
      assert_includes logs, "Processing User seat assignment for provisioned user"

      assignment.reload
      assert_equal 1, assignment.seats.count
      assert_dogstats_increment(1, "copilot.external_identity_job.seat_inserted", tags: ["type:user"])
    end

    test "doesn't create user level seat if team seat already exists" do
      identity = create(:external_identity)
      user = identity.user
      organization = identity.target

      team = create(:team, organization: organization)
      team.add_member(user)
      team_assignment = create(:copilot_seat_assignment, assignable: team, organization: organization)
      team_assignment.convert_to_seats
      assert_equal 1, team_assignment.seats.count

      user_assignment = create(:copilot_seat_assignment, assignable: user, organization: organization)
      assert_equal 0, user_assignment.seats.count

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
      assert_includes logs, "User already has a seat for this organization"
      refute_includes logs, "User's teams have no team level seat assignments"
      refute_includes logs, "Processing User seat assignment for provisioned user"

      user_assignment.reload
      assert_equal 0, user_assignment.seats.count
      refute_dogstats_increment("copilot.external_identity_job.seat_inserted", tags: ["type:user"])
    end
  end

  context "Proxima", skip_enterprise: true do
    test "sets tenant based on user" do
      business = create(:business, :enterprise_managed)
      emu = create(:emu, business: business)

      on_multi_tenant_enterprise do
        GitHub::CurrentTenant.remove
        assert_nil GitHub::CurrentTenant.get

        Copilot::SeatManagement::ExternalIdentityJob.perform_now(
          user_id: emu.id,
          external_identity_id: 1,
          transaction_id: "1234",
          action: :provision,
          payload: {}
        )
        assert_equal business, GitHub::CurrentTenant.get
      end
    end
  end
end if GitHub.copilot_enabled?
