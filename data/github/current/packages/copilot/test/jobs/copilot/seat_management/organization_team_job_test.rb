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
    GitHub.flipper[:copilot_seat_assignment_job].enable
    GitHub.flipper[:org_team_job_redirect_seat].disable
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
  end

  context "add_member" do
    context "with org_team_job_redirect_seat feature flag disabled" do
      test "does nothing for a user with an existing seat not pending cancellation" do
        org = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        org.add_member(user)
        team = create(:team, organization: org)
        team.add_member(user)
        create(:copilot_seat_assignment, :team, assignable: team, organization: org)
        user_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: org)
        user_assignment.convert_to_seats
        Copilot::Seat.where(copilot_seat_assignment_id: user_assignment.id).first

        Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).never
        assert_nil user_assignment.pending_cancellation_date

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

        assert_match "Existing Seat found for User", logs
      end

      test "does nothing for a user with an existing seat that is pending cancellation" do
        org = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        org.add_member(user)
        team = create(:team, organization: org)
        team.add_member(user)
        create(:copilot_seat_assignment, :team, assignable: team, organization: org)
        user_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: org)
        user_assignment.convert_to_seats
        user_assignment.update!(pending_cancellation_date: Time.current + 1.day)

        Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).never
        refute_nil user_assignment.pending_cancellation_date

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

        assert_match "Existing Seat found for User", logs
      end
    end

    context "with org_team_job_redirect_seat feature flag enabled" do
      test "does nothing for a user with an existing seat that is not pending cancellation" do
        GitHub.flipper[:org_team_job_redirect_seat].enable
        org = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        org.add_member(user)
        team = create(:team, organization: org)
        team.add_member(user)
        create(:copilot_seat_assignment, :team, assignable: team, organization: org)
        user_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: org)
        user_assignment.convert_to_seats

        assert_nil user_assignment.pending_cancellation_date
        Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).never

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

        assert_match "Existing Seat found for User", logs
      end

      test "points user seat with user seat assignment that is pending cancellation to the team seat assignment" do
        GitHub.flipper[:org_team_job_redirect_seat].enable
        org = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        org.add_member(user)
        team = create(:team, organization: org)
        team.add_member(user)
        team_assignment = create(:copilot_seat_assignment, :team, assignable: team, organization: org)
        user_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: org)
        user_assignment.convert_to_seats
        user_assignment.update!(pending_cancellation_date: Time.current + 1.day)
        user_seat = Copilot::Seat.where(copilot_seat_assignment_id: user_assignment.id).first

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
        GitHub.flipper[:org_team_job_redirect_seat].enable
        org = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        org.add_member(user)

        team1 = create(:team, organization: org)
        team1.add_member(user)
        team1_assignment = create(:copilot_seat_assignment, :team, assignable: team1, organization: org)
        team1_assignment.convert_to_seats
        team1_assignment.update!(pending_cancellation_date: Time.current + 1.day)

        user_seat = Copilot::Seat.where(assigned_user_id: user.id).first

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
        GitHub.flipper[:org_team_job_redirect_seat].enable
        org = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        org.add_member(user)

        team1 = create(:team, organization: org)
        team1.add_member(user)
        team1.add_member(create(:user))
        team1_assignment = create(:copilot_seat_assignment, :team, assignable: team1, organization: org)
        team1_assignment.convert_to_seats
        team1_assignment.update!(pending_cancellation_date: Time.current + 1.day)

        user_seat = Copilot::Seat.where(assigned_user_id: user.id).first

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
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      team = create(:team, organization: organization)
      team.add_member(user)
      create(:copilot_seat_assignment, :team, assignable: team, organization: organization)

      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).with(organization.id, user.id).once

      logs = capture_logs do
        assert_changes -> { Copilot::Seat.count } do
          assert_changes -> { Copilot::SeatHistory.count } do
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
      end
      assert_match "Creating seat for user with Team SeatAssignment", logs
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
        assert_match "Creating User SeatAssignment to disassociate", logs
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
      assert_match "Creating User SeatAssignment to disassociate", logs
      assert_match "Associating user's seat with disassociated SeatAssignment", logs
      refute Copilot::SeatAssignment.exists?(team_assignment.id)
      assert Copilot::SeatAssignment.exists?(assignable: user, organization: organization)
      assert Copilot::SeatAssignment.exists?(assignable: user2, organization: organization)
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
      assert_match "Creating User SeatAssignment to disassociate", logs
      assert_match "Associating user's seat with disassociated SeatAssignment", logs
      refute Copilot::SeatAssignment.exists?(team_assignment.id)
      assert Copilot::SeatAssignment.exists?(
        assignable: user,
        organization: organization,
        assigning_user: other_admin,
      )
      refute Copilot::SeatAssignment.exists?(
        assignable: user,
        organization: organization,
        assigning_user: admin,
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

  context "remove_member" do
    test "does nothing for a user without an existing seat" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      team = create(:team, organization: organization)
      team.add_member(user)
      create(:copilot_seat_assignment, :team, assignable: team, organization: organization)

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

      assert_match "User Seat doesn't exist for this organization", logs
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
              action: :remove_member,
              transaction_id: "1234",
              payload: { foo: "bar" },
            )
          end
        end
      end

      assert_match "Seat for suspended user has been canceled", logs
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
        refute_match "Creating User SeatAssignment to disassociate", logs
        assert_dogstats_increment(1, "copilot.organization_team_job.member_removed.existing_seat_updated")

        assert_equal team_assignment2, user_seat.reload.seat_assignment

        assert_hydro_messages(count: 0, schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentCreated")
      end
    end

    test "Creates and unassigns user seat assignment for removed user" do
      freeze_time do
        organization = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        team = create(:team, organization: organization)
        team.add_member(user)
        team_assignment = create(:copilot_seat_assignment, :team, assignable: team, organization: organization)
        team_assignment.convert_to_seats

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).with(instance_of(Copilot::SeatAssignment), nil, :team_member_removed_disassociate_seat).once

        logs = capture_logs do
          assert_changes -> { Copilot::SeatAssignment.count } do
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
        assert_match "Creating User SeatAssignment to disassociate", logs
        assert_match "Associating user's seat with disassociated SeatAssignment", logs

        user_seat_assignment = Copilot::SeatAssignment.where(assignable: user).last
        refute_nil user_seat_assignment.pending_cancellation_date

        # update pending cancellation date so that assignment matches state when hydro msg is sent
        user_seat_assignment.update_column(:pending_cancellation_date, nil)

        assert_hydro_messages(count: 1, schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentCreated")
      end
    end

    test "points user seat at existing user seat assignment and unassigns it" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      team = create(:team, organization: organization)
      team.add_member(user)
      team_assignment = create(:copilot_seat_assignment, :team, assignable: team, organization: organization)
      team_assignment.convert_to_seats
      user_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization)

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
      assert_match "User somehow already has User SeatAssignment, not creating one to disassociate.", logs
    end

    test "removes seat for user removed from org and team with team seat assignment" do
      GitHub.stubs(:subscribe)
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      team = create(:team, organization: organization)
      team.add_member(user)
      team_assignment = create(:copilot_seat_assignment, :team, assignable: team, organization: organization)
      team_assignment.convert_to_seats

      ::Organization.any_instance.stubs(:member_ids).returns([])
      ::Organization.any_instance.stubs(:member?).returns(false)

      logs = capture_logs do
        assert_no_changes -> { Copilot::SeatAssignment.count } do
          assert_changes -> { Copilot::Seat.count } do
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
      end

      assert_match "User is no longer part of organization", logs
      refute Copilot::Seat.for_user(user).first.present?
    end
  end
end if GitHub.copilot_enabled?
