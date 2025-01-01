# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::SeatAssignments::OrganizationConverterCommandTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include DogstatsTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).never
  end

  context "initialize" do
    test "raises an error if the seat assignment is not an organization" do
      assert_raises(TypeError) do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatAssignments::OrganizationConverterCommand.call("not an organization")
        end
      end

      assert_raises(Copilot::Errors::SeatAssignmentError) do
        team_assignment = create(:copilot_seat_assignment, :team)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatAssignments::OrganizationConverterCommand.call(team_assignment)
        end
      end
    end

    test "raises an error if the associated organization isn't valid" do
      assert_raises(Copilot::Errors::SeatAssignmentError) do
        seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatAssignments::OrganizationConverterCommand.call(seat_assignment)
        end
      end
    end

    test "raises an error if the organization isn't the assigned organization" do
      assert_raises(Copilot::Errors::SeatAssignmentAssignableError) do
        organization = create(:copilot_for_business_enabled_organization)
        seat_assignment = create(:copilot_seat_assignment, :organization)
        refute_equal organization, seat_assignment.organization
        seat_assignment.update_column(:owner_id, organization.id) # make the organization invalid
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatAssignments::OrganizationConverterCommand.call(seat_assignment)
        end
      end
    end
  end

  context "perform" do
    test "creates a seat for every single member" do
      user = create(:user)
      organization = create(:copilot_for_business_enabled_organization)
      organization.add_member(user)
      user_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user, assigning_user: organization.admin)
      create(:copilot_seat, organization: organization, assigned_user: user, seat_assignment: user_seat_assignment)

      organization.add_member(create(:user))
      organization.add_member(create(:user))
      organization.add_member(create(:user))
      # we should have 5 members now - org admin and 4 users
      assert_equal 5, organization.members.count

      seat_assignment = create(:copilot_seat_assignment, :organization, organization: organization, assigning_user: organization.admin)
      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization.id).once
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).once
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatAssignments::OrganizationConverterCommand.call(seat_assignment)
      end

      assert_equal 5, Copilot::Seat.for_owner(organization).count
      refute Copilot::SeatAssignment.exists?(user_seat_assignment.id)
    end

    test "creates a seat for every single member that is not suspended" do
      user = create(:user)
      organization = create(:copilot_for_business_enabled_organization)
      organization.add_member(user)
      user_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user, assigning_user: organization.admin)
      create(:copilot_seat, organization: organization, assigned_user: user, seat_assignment: user_seat_assignment)

      suspended_user = create(:user)
      organization.add_member(suspended_user)
      suspended_user.update_column(:suspended_at, Time.current)
      organization.add_member(create(:user))
      organization.add_member(create(:user))
      # we should have 5 members now - org admin and 4 users
      assert_equal 5, organization.members.count

      seat_assignment = create(:copilot_seat_assignment, :organization, organization: organization, assigning_user: organization.admin)
      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization.id).once
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).once
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatAssignments::OrganizationConverterCommand.call(seat_assignment)
      end

      assert_equal 4, Copilot::Seat.for_owner(organization).count
      refute Copilot::SeatAssignment.exists?(user_seat_assignment.id)
    end

    test "handles org assignment when there are existing cancelled team seats" do
      assert_equal 0, Copilot::Seat.count
      assert_equal 0, Copilot::SeatAssignment.count

      organization = create(:copilot_for_business_enabled_organization)
      team = create(:team, organization: organization)

      5.times do
        user = create(:user)
        organization.add_member(user)
        team.add_member(user)
      end

      organization.reload
      assert_equal 6, organization.member_ids.count
      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization.id).twice
      # create seats for the team pending cancellation
      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: team, assigning_user: organization.admin)
      seat_assignment.convert_to_seats
      seat_assignment.unassign!(organization.admin)

      organization.reload
      assert_equal 6, organization.member_ids.count
      assert_equal 5, Copilot::Seat.count
      assert_equal 1, Copilot::SeatAssignment.count
      refute Copilot::SeatAssignment.first.pending_cancellation_date.nil?

      # seat assignment for the organization
      org_assignment = create(:copilot_seat_assignment, organization: organization, assignable: organization)

      organization.reload
      assert_equal 6, organization.member_ids.count
      assert_equal 5, Copilot::Seat.count
      # have two seat assignments now, one for the org and one for the team
      assert_equal 2, Copilot::SeatAssignment.count

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).once

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatAssignments::OrganizationConverterCommand.call(org_assignment)
        assert_equal 6, Copilot::Seat.count # everyone has a seat because org assignment
        assert Copilot::Seat.all.all? { |seat| seat.copilot_seat_assignment_id == org_assignment.id }
      end
    end

    test "handles org assignment when there are seats for users not in the org" do
      assert_equal 0, Copilot::Seat.count
      assert_equal 0, Copilot::SeatAssignment.count

      organization = create(:copilot_for_business_enabled_organization)
      team = create(:team, organization: organization)

      5.times do
        user = create(:user)
        organization.add_member(user)
        team.add_member(user)
      end

      organization.reload
      assert_equal 6, organization.member_ids.count
      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization.id).at_least_once
      # create seats for the team pending cancellation
      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: team, assigning_user: organization.admin)
      seat_assignment.convert_to_seats
      seat_assignment.unassign!(organization.admin)

      organization.reload
      assert_equal 6, organization.member_ids.count
      assert_equal 5, Copilot::Seat.count
      assert_equal 1, Copilot::SeatAssignment.count
      refute Copilot::SeatAssignment.first.pending_cancellation_date.nil?

      # we need to create a user outside of the org and FORCE them to have a seat to simulate a bug
      user = create(:user)
      seat = Copilot::Seat.new(
        assigned_user: user,
        organization: organization,
        seat_assignment: seat_assignment
      )
      seat.save(validate: false)

      assert_equal 6, organization.member_ids.count
      assert_equal 6, Copilot::Seat.count
      assert_equal 1, Copilot::SeatAssignment.count

      # seat assignment for the organization
      org_assignment = create(:copilot_seat_assignment, organization: organization, assignable: organization)

      organization.reload
      assert_equal 6, organization.member_ids.count
      assert_equal 6, Copilot::Seat.count
      # have two seat assignments now, one for the org and one for the team
      assert_equal 2, Copilot::SeatAssignment.count

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).once

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatAssignments::OrganizationConverterCommand.call(org_assignment)
        assert_equal 6, Copilot::Seat.count # everyone has a seat and deleted non-org member because org assignment
        assert Copilot::Seat.all.all? { |seat| seat.copilot_seat_assignment_id == org_assignment.id }
        assert_equal 1, Copilot::SeatAssignment.for_owner(organization).count
      end
    end

    test "doesn't run if it can't get a lock" do
      organization = create(:copilot_for_business_enabled_organization)
      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: organization)

      lock_key = "organization-converter-command-#{organization.id}"
      restraint = GitHub::Restraint.new

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).never
      restraint.lock!(lock_key, 1, 5.minutes) do
        assert_raises GitHub::Restraint::UnableToLock do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatAssignments::OrganizationConverterCommand.call(seat_assignment)
          end
        end
      end
    end

    test "doesn't run if seat assignment is pending cancellation" do
      organization = create(:copilot_for_business_enabled_organization)
      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: organization, pending_cancellation_date: Date.today)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).never
      ActiveRecord::Base.connected_to(role: :reading) do
        assert_raises(Copilot::Errors::SeatAssignmentPendingCancellationError) do
          Copilot::SeatAssignments::OrganizationConverterCommand.call(seat_assignment)
        end
      end
    end
  end
end if GitHub.copilot_enabled?
