# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/missing_record_helper"

class Copilot::SeatManagement::OrganizationTeamJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  include MissingRecordHelper
  include HydroTestHelpers
  include DogstatsTestHelpers

  setup do
    enable_feature_flag(:copilot_seat_assignment_job)
    disable_feature_flag(:copilot_revokable_access)
  end

  sig { returns([::Organization, User, Team, Copilot::SeatAssignment]) }
  def create_hierarchy
    org = create(:copilot_for_business_enabled_organization)
    user = create(:user)
    org.add_member(user)
    team = create(:team, organization: org)
    team.add_member(user)
    team_assignment = create(
      :copilot_seat_assignment,
      :team,
      assignable: team,
      owner: org,
      assigning_user: org.admins.first
    )

    [org, user, team, team_assignment]
  end

  context "perform" do
    test "raises an error if the action is invalid" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      team = create(:team, organization: organization)
      action = :invalid_action

      assert_raises(ArgumentError) do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrganizationTeamJob.perform_now(
            organization_id: organization.id,
            team_id: team.id,
            user_id: user.id,
            action: action,
            transaction_id: "1234",
            payload: { foo: "bar" },
          )
        end
      end
    end

    test "does nothing with fake org" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      team = create(:team, organization: organization)
      action = :add_member

      logs = capture_logs do
        Copilot::ErrorReporter.expects(:report!).with do |error, context|
          error.is_a?(Copilot::Errors::CopilotError) &&
          context[:extra_details]["gh.organization.id"] == 233552342
        end
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrganizationTeamJob.perform_now(
            organization_id: 233552342,
            team_id: team.id,
            user_id: user.id,
            action: action,
            transaction_id: "1234",
            payload: { foo: "bar" },
          )
        end
      end

      assert_match "Invalid Organization", logs
    end

    test "does nothing with fake user_id" do
      organization = create(:copilot_for_business_enabled_organization)
      user = missing(:user)
      team = create(:team, organization: organization)
      action = :add_member

      logs = capture_logs do
        Copilot::ErrorReporter.expects(:report!).with do |error, context|
          error.is_a?(Copilot::Errors::CopilotError) &&
          context[:extra_details]["gh.user.id"] == user.id
        end
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrganizationTeamJob.perform_now(
            organization_id: organization.id,
            team_id: team.id,
            user_id: user.id,
            action: action,
            transaction_id: "1234",
            payload: { foo: "bar" },
          )
        end
      end

      assert_match "Invalid User", logs
    end

    test "resolves tenant on a multi-tenant enterprise with business owner" do
      on_multi_tenant_enterprise do
        # Simulate no tenant being set
        GitHub::CurrentTenant.remove
        assert_nil GitHub::CurrentTenant.get

        user = create(:user)
        business = create(:business)
        organization = create(:organization, business: business, admin: user)
        team = create(:team, organization: organization)

        Copilot::SeatManagement::OrganizationTeamJob.perform_now(
          organization_id: 233552342,
          team_id: team.id,
          user_id: user.id,
          action: :add_member,
          transaction_id: "1234",
          payload: { foo: "bar" },
        )

        refute_nil GitHub::CurrentTenant.get
        assert_equal business, GitHub::CurrentTenant.get
      end
    end
  end

  context "add_member" do
    test "does nothing for a user with an existing seat that is not pending cancellation" do
      org, user, team = create_hierarchy
      user_assignment = create(:copilot_seat_assignment, :user, assignable: user, owner: org, assigning_user: org.admins.first)
      user_assignment.convert_to_seats

      assert_nil user_assignment.pending_cancellation_date
      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).never
      Copilot::SeatAssignment.any_instance.expects(:reinstate_access!).once if GitHub.flipper[:copilot_revokable_access].enabled?

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count + Copilot::SeatHistory.count + Copilot::SeatAssignment.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::OrganizationTeamJob.perform_now(
              organization_id: org.id,
              team_id: team.id,
              user_id: user.id,
              action: :add_member,
              transaction_id: "1234",
              payload: { foo: "bar" },
            )
          end
        end
      end

      assert_dogstats_increment(1, "copilot.organization_team_job.member_added.access_reinstated") if GitHub.flipper[:copilot_revokable_access].enabled?
      assert_match "Existing Seat found for User", logs
    end

    test "wont attempt to reistate access for existing seats pointing to a non-user seat assignment that is not pending cancellation" do
      enable_feature_flag(:copilot_revokable_access)

      org, user, team = create_hierarchy

      other_team = create(:team, organization: org)
      other_team.add_member(user)
      other_team_assignment = create(:copilot_seat_assignment, :team, organization: org, assignable: other_team, owner: org, assigning_user: org.admins.first)
      create(:copilot_seat, assigned_user: user, seat_assignment: other_team_assignment, organization: org)

      Copilot::SeatAssignment.any_instance.expects(:reinstate_access!).never
      refute_dogstats_increment("copilot.organization_team_job.member_added.access_reinstated")

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::OrganizationTeamJob.perform_now(
          organization_id: org.id,
          team_id: team.id,
          user_id: user.id,
          action: :add_member,
          transaction_id: "1234",
          payload: { foo: "bar" },
        )
      end
    end

    test "points user seat with user seat assignment that is pending cancellation to the team seat assignment" do
      org, user, team, team_assignment = create_hierarchy
      user_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: org)
      user_assignment.convert_to_seats
      user_assignment.update!(pending_cancellation_date: Time.current + 1.day)
      user_seat = Copilot::Seat.where(copilot_seat_assignment_id: user_assignment.id).first!

      refute_nil user_assignment.pending_cancellation_date

      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).never

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count + Copilot::SeatHistory.count } do
          assert_changes -> { Copilot::SeatAssignment.count }, -1 do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationTeamJob.perform_now(
                organization_id: org.id,
                team_id: team.id,
                user_id: user.id,
                action: :add_member,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
      end

      assert_match "Existing Seat found for User", logs
      assert_match "Existing Seat pending cancellation was found, updating it to point at Team SeatAssignment", logs
      assert_match "Old SeatAssignment has no associated seats anymore, destroying it.", logs
      assert_dogstats_increment(1, "copilot.organization_team_job.member_added.existing_seat_updated")
      assert_empty Copilot::SeatAssignment.where(id: user_assignment.id)
      assert user_seat.reload.copilot_seat_assignment_id == team_assignment.id
    end

    test "points user seat with team seat assignment that is pending cancellation to the team seat assignment" do
      org = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      org.add_member(user)

      team1 = create(:team, organization: org)
      team1.add_member(user)
      team1_assignment = create(:copilot_seat_assignment, :team, assignable: team1, organization: org)
      team1_assignment.convert_to_seats
      team1_assignment.update!(pending_cancellation_date: Time.current + 1.day)

      user_seat = Copilot::Seat.where(assigned_user_id: user.id).first!

      team2 = create(:team, organization: org)
      team2_assignment = create(:copilot_seat_assignment, :team, assignable: team2, organization: org)
      team2_assignment.convert_to_seats

      team2.add_member(user)

      refute_nil team1_assignment.pending_cancellation_date
      assert_equal team1_assignment, user_seat.seat_assignment

      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).never

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count + Copilot::SeatHistory.count } do
          assert_changes -> { Copilot::SeatAssignment.count }, -1 do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationTeamJob.perform_now(
                organization_id: org.id,
                team_id: team2.id,
                user_id: user.id,
                action: :add_member,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
      end

      assert_match "Existing Seat found for User", logs
      assert_match "Existing Seat pending cancellation was found, updating it to point at Team SeatAssignment", logs
      assert_match "Old SeatAssignment has no associated seats anymore, destroying it.", logs
      assert_empty Copilot::SeatAssignment.where(id: team1_assignment.id)
      assert user_seat.reload.copilot_seat_assignment_id == team2_assignment.id
    end

    test "points user seat with team seat assignment that is pending cancellation to the team seat assignment, does not destroy the old assignment if there are still seats" do
      org = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      org.add_member(user)

      team1 = create(:team, organization: org)
      team1.add_member(user)
      team1.add_member(create(:user))
      team1_assignment = create(:copilot_seat_assignment, :team, assignable: team1, organization: org)
      team1_assignment.convert_to_seats
      team1_assignment.update!(pending_cancellation_date: Time.current + 1.day)

      user_seat = Copilot::Seat.where(assigned_user_id: user.id).first!

      team2 = create(:team, organization: org)
      team2_assignment = create(:copilot_seat_assignment, :team, assignable: team2, organization: org)
      team2_assignment.convert_to_seats

      team2.add_member(user)

      refute_nil team1_assignment.pending_cancellation_date
      assert_equal team1_assignment, user_seat.seat_assignment

      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).never

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count + Copilot::SeatHistory.count } do
          assert_no_changes -> { Copilot::SeatAssignment.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationTeamJob.perform_now(
                organization_id: org.id,
                team_id: team2.id,
                user_id: user.id,
                action: :add_member,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
      end

      assert_match "Existing Seat found for User", logs
      assert_match "Existing Seat pending cancellation was found, updating it to point at Team SeatAssignment", logs
      refute_match "Old SeatAssignment has no associated seats anymore, destroying it.", logs
      assert_equal 1, team1_assignment.seats.count
      assert user_seat.reload.copilot_seat_assignment_id == team2_assignment.id
    end

    test "does nothing for a user if there is no team seat assignment" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      team = create(:team, organization: organization)
      team.add_member(user)

      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).never

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count + Copilot::SeatHistory.count + Copilot::SeatAssignment.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::OrganizationTeamJob.perform_now(
              organization_id: organization.id,
              team_id: team.id,
              user_id: user.id,
              action: :add_member,
              transaction_id: "1234",
              payload: { foo: "bar" },
            )
          end
        end
      end
      assert_match "No Team SeatAssignment found", logs
    end

    test "adds user to seat with a team seat assignment" do
      org, user, team = create_hierarchy

      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).with(org.id, user.id).once

      logs = capture_logs do
        assert_changes -> { Copilot::Seat.count } do
          assert_changes -> { Copilot::SeatHistory.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationTeamJob.perform_now(
                organization_id: org.id,
                team_id: team.id,
                user_id: user.id,
                action: :add_member,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
      end
      assert_match "Created seat for user with Team SeatAssignment", logs
    end
  end

  context "destroy_team" do
    test "does nothing if the team has no seat assignment" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      team = create(:team, organization: organization)
      team.add_member(user)

      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).never

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count + Copilot::SeatHistory.count + Copilot::SeatAssignment.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::OrganizationTeamJob.perform_now(
              organization_id: organization.id,
              team_id: team.id,
              user_id: user.id,
              action: :destroy_team,
              transaction_id: "1234",
              payload: { foo: "bar" },
            )
          end
        end
      end
      assert_match "No Team SeatAssignment found", logs
    end

    test "cancels seat of a suspended user" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      team = create(:team, organization: organization)
      team.add_member(user)
      team_assignment = create(:copilot_seat_assignment, :team, assignable: team, organization: organization)
      create(:copilot_seat, assigned_user: user, seat_assignment: team_assignment)

      user.suspend("naughty")

      logs = capture_logs do
        assert_changes -> { Copilot::Seat.count }, -1 do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::OrganizationTeamJob.perform_now(
              organization_id: organization.id,
              team_id: team.id,
              user_id: user.id,
              action: :destroy_team,
              transaction_id: "1234",
              payload: { foo: "bar" },
            )
          end
        end
      end

      assert_match "Seat for suspended user has been canceled", logs
    end

    test "does not cancel the seat and unassigns assignment for a suspended user when copilot_revokable_access flag is enabled" do
      enable_feature_flag(:copilot_revokable_access)
      org, user, team, team_assignment = create_hierarchy
      create(:copilot_seat, assigned_user: user, seat_assignment: team_assignment)

      user.suspend("naughty")

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::OrganizationTeamJob.perform_now(
              organization_id: org.id,
              team_id: team.id,
              user_id: user.id,
              action: :destroy_team,
              transaction_id: "1234",
              payload: { foo: "bar" },
            )
          end
        end
      end

      assignment = Copilot::SeatAssignment.find_by(assignable: user)
      assert_nil assignment&.access_revoked_at
      refute_nil assignment&.pending_cancellation_date
      refute_empty assignment&.seats
      refute_match "Seat for suspended user has been canceled", logs
    end

    # This is very unlikely and should only happen if there is a race condition in which a team is destroyed AND a user
    # is removed from the org at the same time.
    test "does not cancel the seat and revokes access for a user removed from the org when copilot_revokable_access flag is enabled" do
      enable_feature_flag(:copilot_revokable_access)
      org, user, team, team_assignment = create_hierarchy
      create(:copilot_seat, assigned_user: user, seat_assignment: team_assignment)

      ::Organization.any_instance.stubs(:member_ids).returns([org.admins.first.id])

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::OrganizationTeamJob.perform_now(
              organization_id: org.id,
              team_id: team.id,
              user_id: user.id,
              action: :destroy_team,
              transaction_id: "1234",
              payload: { foo: "bar" },
            )
          end
        end
      end

      refute_nil Copilot::SeatAssignment.find_by(assignable: user)&.access_revoked_at
      refute_match "Seat for suspended user has been canceled", logs
    end

    test "Repoints seat at other active team assignment if user is part of multiple teams" do
      freeze_time do
        organization = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        user2 = create(:user)
        team = create(:team, organization: organization)
        team2 = create(:team, organization: organization)
        team3 = create(:team, organization: organization)

        team.add_member(user)
        team.add_member(user2)
        team2.add_member(user)
        team3.add_member(user)

        team_assignment = create(:copilot_seat_assignment, :team, assignable: team, organization: organization)
        team_assignment2 = create(:copilot_seat_assignment, :team, assignable: team2, organization: organization)
        create(:copilot_seat_assignment, :team, assignable: team3, organization: organization, pending_cancellation_date: 2.days.from_now)

        user_seat = create(:copilot_seat, assigned_user: user, seat_assignment: team_assignment)
        user2_seat = create(:copilot_seat, assigned_user: user2, seat_assignment: team_assignment)

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).with(team_assignment, nil, :team_destroyed).once
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).with(instance_of(Copilot::SeatAssignment), nil, :team_destroyed_disassociate_seat).once

        logs = capture_logs do
          assert_no_changes -> { Copilot::SeatAssignment.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationTeamJob.perform_now(
                organization_id: organization.id,
                team_id: team.id,
                user_id: user.id,
                action: :destroy_team,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
        assert_match "Found another Team SeatAssignment to point Seat at", logs
        assert_match "Created User SeatAssignment to disassociate", logs
        assert_match "Associating user's seat with disassociated SeatAssignment", logs

        refute Copilot::SeatAssignment.exists?(team_assignment.id)
        assert_equal team_assignment2, user_seat.reload.seat_assignment
        refute_equal team_assignment, user2_seat.reload.seat_assignment
        refute_nil user2_seat.seat_assignment.pending_cancellation_date
        assert_dogstats_increment(1, "copilot.organization_team_job.team_destroyed.existing_seat_updated")

        assert_hydro_messages(count: 1, schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentCreated")
      end
    end

    test "Unassigns team seat assignment and creates User SeatAssignments for members to disassociate" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)

      team = create(:team, organization: organization)
      team_id = team.id
      team.add_member(user)

      user2 = create(:user)
      team.add_member(user2)

      team_assignment = create(:copilot_seat_assignment, :team, assignable: team, organization: organization)
      team_assignment.convert_to_seats

      # Mimic the state where the team has been destroyed by the time this job gets called
      team.destroy

      assert_nil team_assignment.pending_cancellation_date
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).with(team_assignment, nil, :team_destroyed).once
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).with(instance_of(Copilot::SeatAssignment), nil, :team_destroyed_disassociate_seat).twice

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count + Copilot::SeatHistory.count } do
          assert_changes -> { Copilot::SeatAssignment.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationTeamJob.perform_now(
                organization_id: organization.id,
                team_id: team_id,
                user_id: user.id,
                action: :destroy_team,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
      end

      assert_match "Team was destroyed. Unassigning Team SeatAssignment", logs
      assert_match "Created User SeatAssignment to disassociate", logs
      assert_match "Associating user's seat with disassociated SeatAssignment", logs
      refute Copilot::SeatAssignment.exists?(team_assignment.id)

      assert Copilot::SeatAssignment.exists?(assignable: user, owner_id: organization.id, owner_type: "Organization")
      assert Copilot::SeatAssignment.exists?(assignable: user2, owner_id: organization.id, owner_type: "Organization")
      assert_nil Copilot::SeatAssignment.find_by(assignable: user)&.access_revoked_at if GitHub.flipper[:copilot_revokable_access].enabled?
      assert_nil Copilot::SeatAssignment.find_by(assignable: user2)&.access_revoked_at if GitHub.flipper[:copilot_revokable_access].enabled?
    end

    test "creates new user seat assignments with remaining admin if the original assigning user doesn't exist in the org anymore" do
      organization = create(:copilot_for_business_enabled_organization)
      admin = organization.admins.first
      user = create(:user)
      other_user = create(:user)

      # add another admin
      other_admin = create(:user)
      organization.add_admin(other_admin)
      organization.reload

      team = create(:team, organization: organization)
      team_id = team.id
      team.add_member(user)
      team.add_member(other_user)

      team_assignment = create(:copilot_seat_assignment, :team, assignable: team, organization: organization, assigning_user: admin)
      team_assignment.convert_to_seats

      # Mimic removal of original assigning_user
      organization.remove_member!(admin)
      organization.reload

      assert_nil team_assignment.pending_cancellation_date

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count + Copilot::SeatHistory.count } do
          assert_changes -> { Copilot::SeatAssignment.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationTeamJob.perform_now(
                organization_id: organization.id,
                team_id: team_id,
                user_id: user.id,
                action: :destroy_team,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
      end

      assert_match "Team was destroyed. Unassigning Team SeatAssignment", logs
      assert_match "Created User SeatAssignment to disassociate", logs
      assert_match "Associating user's seat with disassociated SeatAssignment", logs
      refute Copilot::SeatAssignment.exists?(team_assignment.id)
      assert Copilot::SeatAssignment.exists?(
        assignable: user,
        assigning_user: other_admin,
        owner_id: organization.id,
        owner_type: "Organization"
      )
      refute Copilot::SeatAssignment.exists?(
        assignable: user,
        assigning_user: admin,
        owner_id: organization.id,
        owner_type: "Organization"
      )
    end

    test "Calls OrganizationCleaner and removes SeatAssignment and Seats if the Org no longer exists" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      user2 = create(:user)
      team = create(:team, organization: organization)
      team.add_member(user)
      team.add_member(user2)

      team_assignment = create(:copilot_seat_assignment, :team, assignable: team, organization: organization)
      team_assignment.convert_to_seats

      seat = team_assignment.seats.first
      seat2 = team_assignment.seats.second

      assert Copilot::Seat.exists?(seat.id)
      assert Copilot::Seat.exists?(seat2.id)

      organization.destroy

      logs = capture_logs do
        assert_changes -> { Copilot::Seat.count } do
          assert_changes -> { Copilot::SeatAssignment.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationTeamJob.perform_now(
                organization_id: organization.id,
                team_id: team.id,
                user_id: user.id,
                action: :destroy_team,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
      end

      refute_match "Team was destroyed. Unassigning Team SeatAssignment", logs
      assert_match "Organization not found, calling OrganizationCleaner", logs
      refute Copilot::SeatAssignment.exists?(team_assignment.id)
      refute Copilot::Seat.exists?(seat.id)
      refute Copilot::Seat.exists?(seat2.id)
    end
  end

  context ":remove_member" do
    test "does nothing for a user without an existing seat" do
      org, user, team = create_hierarchy

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count + Copilot::SeatHistory.count + Copilot::SeatAssignment.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::OrganizationTeamJob.perform_now(
              organization_id: org.id,
              team_id: team.id,
              user_id: user.id,
              action: :remove_member,
              transaction_id: "1234",
              payload: { foo: "bar" },
            )
          end
        end
      end

      assert_match "User Seat doesn't exist for this organization", logs
    end

    test "cancels seat of a suspended user when copilot_revokable_access flag is disabled" do
      org, user, team, team_assignment = create_hierarchy
      create(:copilot_seat, assigned_user: user, seat_assignment: team_assignment)

      user.suspend("naughty")

      logs = capture_logs do
        assert_changes -> { Copilot::Seat.count }, -1 do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::OrganizationTeamJob.perform_now(
              organization_id: org.id,
              team_id: team.id,
              user_id: user.id,
              action: :remove_member,
              transaction_id: "1234",
              payload: { foo: "bar" },
            )
          end
        end
      end

      assert_match "Seat for suspended user has been canceled", logs
    end

    test "does not cancel a seat of a suspended user when copilot_revokable_access flag is enabled" do
      enable_feature_flag(:copilot_revokable_access)

      org, user, team, team_assignment = create_hierarchy
      create(:copilot_seat, assigned_user: user, seat_assignment: team_assignment)

      user.suspend("naughty")

      assert_changes -> { Copilot::SeatAssignment.count }, 1 do
        assert_no_changes -> { Copilot::Seat.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::OrganizationTeamJob.perform_now(
              organization_id: org.id,
              team_id: team.id,
              user_id: user.id,
              action: :remove_member,
              transaction_id: "1234",
              payload: { foo: "bar" },
            )
          end
        end
      end
    end

    test "does nothing for a team without a seat assignment" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      team = create(:team, organization: organization)
      team.add_member(user)

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count + Copilot::SeatHistory.count + Copilot::SeatAssignment.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::OrganizationTeamJob.perform_now(
              organization_id: organization.id,
              team_id: team.id,
              user_id: user.id,
              action: :remove_member,
              transaction_id: "1234",
              payload: { foo: "bar" },
            )
          end
        end
      end
      assert_match "No Team SeatAssignment found", logs
    end

    test "Repoints seat at other active team assignment if user is part of multiple teams" do
      freeze_time do
        organization = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        team = create(:team, organization: organization)
        team2 = create(:team, organization: organization)
        team3 = create(:team, organization: organization)

        team.add_member(user)
        team2.add_member(user)
        team3.add_member(user)

        team_assignment = create(:copilot_seat_assignment, :team, assignable: team, organization: organization)
        team_assignment2 = create(:copilot_seat_assignment, :team, assignable: team2, organization: organization)
        create(:copilot_seat_assignment, :team, assignable: team3, organization: organization, pending_cancellation_date: 2.days.from_now)

        user_seat = create(:copilot_seat, assigned_user: user, seat_assignment: team_assignment)

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).with(instance_of(Copilot::SeatAssignment), nil, :team_member_removed_disassociate_seat).never

        logs = capture_logs do
          assert_no_changes -> { Copilot::SeatAssignment.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationTeamJob.perform_now(
                organization_id: organization.id,
                team_id: team.id,
                user_id: user.id,
                action: :remove_member,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
        assert_match "Found another Team SeatAssignment to point Seat at", logs
        refute_match "Created User SeatAssignment to disassociate", logs
        assert_dogstats_increment(1, "copilot.organization_team_job.member_removed.existing_seat_updated")

        assert_equal team_assignment2, user_seat.reload.seat_assignment

        assert_hydro_messages(count: 0, schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentCreated")
      end
    end

    test "Cancels seat for removed user who is no longer a team or org member and copilot_revokable_access is disabled" do
      disable_feature_flag(:copilot_revokable_access)
      freeze_time do
        org, user, team, team_assignment = create_hierarchy
        team.add_member(org.admins.first) # seat assignment for team won't be destroyed when user's seat is cancelled and therefore no_changes below

        team_assignment.convert_to_seats

        ::Organization.any_instance.stubs(:member_ids).returns([org.admins.first.id])

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).with(instance_of(Copilot::SeatAssignment), nil, :team_member_removed_disassociate_seat).never

        logs = capture_logs do
          assert_no_changes -> { Copilot::SeatAssignment.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationTeamJob.perform_now(
                organization_id: org.id,
                team_id: team.id,
                user_id: user.id,
                action: :remove_member,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end

        assert_match "User is no longer part of organization, destroying seat", logs
      end
    end

    test "creates and unassigns a seat assignment for a user removed from a team, but not the org, and does not revoke access with flag set" do
      enable_feature_flag(:copilot_revokable_access)
      freeze_time do
        org, user, team, team_assignment = create_hierarchy
        team_assignment.convert_to_seats

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).with(instance_of(Copilot::SeatAssignment), nil, :team_member_removed_disassociate_seat).once

        logs = capture_logs do
          assert_changes -> { Copilot::SeatAssignment.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationTeamJob.perform_now(
                organization_id: org.id,
                team_id: team.id,
                user_id: user.id,
                action: :remove_member,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
        assert_match "Created User SeatAssignment to disassociate", logs
        assert_match "Associating user's seat with disassociated SeatAssignment", logs

        user_seat_assignment = Copilot::SeatAssignment.where(assignable: user).last!
        refute_nil user_seat_assignment.pending_cancellation_date

        # update pending cancellation date so that assignment matches state when hydro msg is sent
        user_seat_assignment.update_column(:pending_cancellation_date, nil)

        assert_hydro_messages(count: 1, schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentCreated")
        assert_nil user_seat_assignment.access_revoked_at if GitHub.flipper[:copilot_revokable_access].enabled?
      end
    end

    test "creates, and unassigns a seat assignment for a suspended user removed from a team, but not the org, with flag set" do
      enable_feature_flag(:copilot_revokable_access)
      freeze_time do
        org, user, team, team_assignment = create_hierarchy
        team_assignment.convert_to_seats

        user.suspend(:naughty)

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).with(instance_of(Copilot::SeatAssignment), nil, :team_member_removed_disassociate_seat).once

        logs = capture_logs do
          assert_changes -> { Copilot::SeatAssignment.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationTeamJob.perform_now(
                organization_id: org.id,
                team_id: team.id,
                user_id: user.id,
                action: :remove_member,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
        assert_match "Created User SeatAssignment to disassociate", logs
        assert_match "Associating user's seat with disassociated SeatAssignment", logs

        user_seat_assignment = Copilot::SeatAssignment.where(assignable: user).last!
        refute_nil user_seat_assignment.pending_cancellation_date

        # update pending cancellation date so that assignment matches state when hydro msg is sent
        user_seat_assignment.update_column(:pending_cancellation_date, nil)

        assert_hydro_messages(count: 1, schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentCreated")
        refute_empty user_seat_assignment.seats
      end
    end

    test "points user seat at existing user seat assignment and unassigns it" do
      org, user, team, team_assignment = create_hierarchy
      team_assignment.convert_to_seats
      user_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: org)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).with(user_assignment, nil, :team_member_removed_disassociate_seat).once

      logs = capture_logs do
        assert_no_changes -> { Copilot::SeatAssignment.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::OrganizationTeamJob.perform_now(
              organization_id: org.id,
              team_id: team.id,
              user_id: user.id,
              action: :remove_member,
              transaction_id: "1234",
              payload: { foo: "bar" },
            )
          end
        end
      end
      refute_nil user_assignment.reload.pending_cancellation_date
      refute_nil user_assignment.access_revoked_at if GitHub.flipper[:copilot_revokable_access].enabled?
      assert_match "Associating user's seat with disassociated SeatAssignment", logs
      assert_match "User already has User SeatAssignment, not creating one to disassociate.", logs
    end

    test "doesn't repoint user seat at existing user seat assignment and if it was already pointing there" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      team = create(:team, organization: organization)
      team.add_member(user)
      team_assignment = create(:copilot_seat_assignment, :team, assignable: team, organization: organization)
      team_assignment.convert_to_seats
      user_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization)
      Copilot::Seat.for_user(user).first&.update_column(:copilot_seat_assignment_id, user_assignment.id)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).with(user_assignment, nil, :team_member_removed_disassociate_seat).once

      logs = capture_logs do
        assert_no_changes -> { Copilot::SeatAssignment.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::OrganizationTeamJob.perform_now(
              organization_id: organization.id,
              team_id: team.id,
              user_id: user.id,
              action: :remove_member,
              transaction_id: "1234",
              payload: { foo: "bar" },
            )
          end
        end
      end
      refute_nil user_assignment.reload.pending_cancellation_date
      refute_nil user_assignment.access_revoked_at if GitHub.flipper[:copilot_revokable_access].enabled?
      assert_match "User already has User SeatAssignment, not creating one to disassociate.", logs
      assert_match "Associating user's seat with disassociated SeatAssignment", logs
    end

    test "does not remove seat or assignment for user removed from org and team with team seat assignment when copilot_revokable_access flag is enabled" do
      enable_feature_flag(:copilot_revokable_access)
      org, user, team, team_assignment = create_hierarchy
      team_assignment.convert_to_seats

      # Simulate removing a user from the org; actual removal calls additional async jobs that
      # we don't need to know about for the purposes of this spec
      ::Organization.any_instance.stubs(:member_ids).returns([org.admins.first.id])

      logs = capture_logs do
        assert_changes -> { Copilot::SeatAssignment.count }, from: 1, to: 2 do
          assert_no_changes -> { Copilot::Seat.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationTeamJob.perform_now(
                organization_id: org.id,
                team_id: team.id,
                user_id: user.id,
                action: :remove_member,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
      end

      user_assignment = Copilot::SeatAssignment.find_by(assignable: user)

      refute_match "User is no longer part of organization", logs
      assert_match "Created User SeatAssignment to disassociate", logs
      assert_match "Associating user's seat with disassociated SeatAssignment", logs

      assert Copilot::Seat.for_user(user).first.present?
      assert user_assignment.present?
      refute_nil user_assignment&.access_revoked_at
      refute_nil user_assignment&.pending_cancellation_date

      # update pending cancellation date so that assignment matches state when hydro msg is sent
      user_assignment&.update_column(:pending_cancellation_date, nil)

      assert_hydro_messages(count: 1, schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentCreated")
    end
  end
end if GitHub.copilot_enabled?
