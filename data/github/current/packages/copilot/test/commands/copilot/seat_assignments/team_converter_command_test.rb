# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::SeatAssignments::TeamConverterCommandTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include DogstatsTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).never
  end

  context "initialize" do
    test "raises an error if the seat assignment is not an team" do
      assert_raises(Copilot::Errors::SeatAssignmentError) do
        assignment = create(:copilot_seat_assignment, :organization)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatAssignments::TeamConverterCommand.call(assignment)
        end
      end

      assert_raises(Copilot::Errors::SeatAssignmentError) do
        assignment = create(:copilot_seat_assignment, :enterprise_team)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatAssignments::TeamConverterCommand.call(assignment)
        end
      end
    end

    test "silly rabbit, you can't assign a team from another organization" do
      seat_assignment = create(:copilot_seat_assignment, :team)
      organization = create(:organization)
      refute_equal organization, seat_assignment.owner

      # change it
      seat_assignment.update_column(:owner_id, organization.id)
      assert_equal organization, seat_assignment.owner
      seat_assignment.reload
      assert_raises(Copilot::Errors::SeatAssignmentAssignableError) do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatAssignments::TeamConverterCommand.call(seat_assignment)
        end
      end
    end
  end

  context "perform" do
    test "Points any existing seats at the seat assignment being converted" do
      assert_equal 0, Copilot::Seat.count
      assert_equal 0, Copilot::SeatAssignment.count

      organization = create(:copilot_for_business_enabled_organization)
      team = create(:team, organization: organization)

      user = create(:user)
      team.add_member(user)

      assert user.organizations.include?(organization)

      other_user = create(:user)
      team.add_member(other_user)

      assert other_user.organizations.include?(organization)

      # other user already has an individual seat
      other_user_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: other_user)
      create(:copilot_seat, organization: organization, assigned_user: other_user, seat_assignment: other_user_seat_assignment)

      # seat assignment for the team
      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: team)

      assert_equal 1, Copilot::Seat.count
      assert_equal 2, Copilot::SeatAssignment.count
      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization.id).once
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).once

      assert_difference "Copilot::Seat.count", 1 do
        ActiveRecord::Base.connected_to(role: :reading) do
          logs = capture_logs do
            Copilot::SeatAssignments::TeamConverterCommand.call(seat_assignment)
          end

          assert_includes logs, "Feature flag disabled, loading members of this team only"
          assert_includes logs, "Loaded list of current team members"
          assert_includes logs, "New seats need to be created"
          assert_includes logs, "Inserted new seats for team members"
          assert_includes logs, "Updated existing seats to point at this Team SeatAssignment"
          assert_dogstats_histogram_value(1, "copilot.seat_assignment_conversion.existing_seats_updated")
        end
      end

      assert Copilot::Seat.all.all? { |seat| seat.copilot_seat_assignment_id == seat_assignment.id }
    end

    test "deletes existing seat if one exists and user is suspended" do
      assert_equal 0, Copilot::Seat.count
      assert_equal 0, Copilot::SeatAssignment.count

      organization = create(:copilot_for_business_enabled_organization)
      team = create(:team, organization: organization)

      user = create(:user)
      team.add_member(user)

      assert user.organizations.include?(organization)

      other_user = create(:user)
      team.add_member(other_user)

      assert other_user.organizations.include?(organization)

      # other user already has an individual seat
      other_user_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: other_user)
      create(:copilot_seat, organization: organization, assigned_user: other_user, seat_assignment: other_user_seat_assignment)

      # suspended other user
      other_user.update_column(:suspended_at, Time.now)
      # seat assignment for the team
      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: team)

      assert_equal 1, Copilot::Seat.count
      assert_equal 2, Copilot::SeatAssignment.count
      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization.id).once
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).once

      assert_no_difference "Copilot::Seat.count" do # we will be deleting one and adding another
        ActiveRecord::Base.connected_to(role: :reading) do
          logs = capture_logs do
            Copilot::SeatAssignments::TeamConverterCommand.call(seat_assignment)
          end

          assert_includes logs, "Feature flag disabled, loading members of this team only"
          assert_includes logs, "Loaded list of current team members"
          assert_includes logs, "New seats need to be created"
          assert_includes logs, "Inserted new seats for team members"
          assert_includes logs, "Updated existing seats to point at this Team SeatAssignment"
          assert_includes logs, "Suspended team members found, destroying their seats"

          # suspended team member's seat is not repointed
          assert_dogstats_histogram_value(0, "copilot.seat_assignment_conversion.existing_seats_updated")
        end
      end

      assert Copilot::Seat.all.all? { |seat| seat.copilot_seat_assignment_id == seat_assignment.id }
    end

    test "handles team assignment when there are existing cancelled organization seats" do
      assert_equal 0, Copilot::Seat.count
      assert_equal 0, Copilot::SeatAssignment.count

      organization = create(:copilot_for_business_enabled_organization)
      team = create(:team, organization: organization)

      5.times do
        user = create(:user)
        organization.add_member(user)
        team.add_member(user)
      end

      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization.id).twice
      # create seats for the organization pending cancellation
      org_assignment = create(:copilot_seat_assignment, organization: organization, assignable: organization, assigning_user: organization.admin)
      org_assignment.convert_to_seats
      org_assignment.unassign!(organization.admin)

      assert_equal 6, Copilot::Seat.count
      assert_equal 1, Copilot::SeatAssignment.count

      # seat assignment for the team
      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: team)

      assert_equal 6, Copilot::Seat.count
      # have two seat assignments now, one for the org and one for the team
      assert_equal 2, Copilot::SeatAssignment.count

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).never

      assert_difference "Copilot::Seat.count", 0 do
        ActiveRecord::Base.connected_to(role: :reading) do
          logs = capture_logs do
            Copilot::SeatAssignments::TeamConverterCommand.call(seat_assignment)
          end
          assert_includes logs, "No new seats need to be created"
          assert_equal 6, Copilot::Seat.count
          # The org admin's seat should still have a cancellation date
          assert !Copilot::Seat.for_user(organization.admin).first&.pending_cancellation_date.nil?
          # seats for team members should not have a cancellation date
          assert Copilot::Seat.for_user(team.member_ids).all? { |seat| seat.pending_cancellation_date.nil? }

          # all 5 team members' seats were repointed to the team seat assignment
          assert_dogstats_histogram_value(5, "copilot.seat_assignment_conversion.existing_seats_updated")
        end
      end
    end

    test "returns an existing seat for another team assignment" do
      assert_equal 0, Copilot::Seat.count
      assert_equal 0, Copilot::SeatAssignment.count

      organization = create(:copilot_for_business_enabled_organization)
      team = create(:team, organization: organization)
      other_team = create(:team, organization: organization)

      user = create(:user)
      team.add_member(user)

      assert user.organizations.include?(organization)

      other_user = create(:user)
      team.add_member(other_user)
      other_team.add_member(other_user)

      assert other_user.organizations.include?(organization)

      # other user already has an individual seat
      other_team_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: other_team)
      create(:copilot_seat, organization: organization, assigned_user: other_user, seat_assignment: other_team_seat_assignment)

      # seat assignment for the team
      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: team)

      assert_equal 1, Copilot::Seat.count
      assert_equal 2, Copilot::SeatAssignment.count
      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization.id).once
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).once
      assert_difference "Copilot::Seat.count", 1 do
        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "Inserted new seats for team members") do
            Copilot::SeatAssignments::TeamConverterCommand.call(seat_assignment)
          end
        end
      end
    end

    test "creates new seats if none exist" do
      organization = create(:copilot_for_business_enabled_organization)
      team = create(:team, organization: organization)

      user = create(:user)
      team.add_member(user)

      assert user.organizations.include?(organization)

      other_user = create(:user)
      team.add_member(other_user)

      assert other_user.organizations.include?(organization)

      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: team)
      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization.id).once
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).once
      assert_difference "Copilot::Seat.count", 2 do
        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "Inserted new seats for team members") do
            Copilot::SeatAssignments::TeamConverterCommand.call(seat_assignment)
          end
        end
      end
    end

    test "creates new seats but not for suspended user if none exist" do
      organization = create(:copilot_for_business_enabled_organization)
      team = create(:team, organization: organization)

      user = create(:user)
      team.add_member(user)

      assert user.organizations.include?(organization)

      other_user = create(:user)
      team.add_member(other_user)

      assert other_user.organizations.include?(organization)
      other_user.update_column(:suspended_at, Time.current)

      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: team)
      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization.id).once
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).once
      assert_difference "Copilot::Seat.count", 1 do
        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "Inserted new seats for team members") do
            Copilot::SeatAssignments::TeamConverterCommand.call(seat_assignment)
          end
        end
      end
    end

    test "can't create a seat if they can't lock" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      team = create(:team, organization: organization)
      team.add_member(user)

      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: team)
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).never
      lock_key = "team-converter-command-#{organization.id}-#{team.id}"
      restraint = GitHub::Restraint.new

      restraint.lock!(lock_key, 1, 5.minutes) do
        assert_raises GitHub::Restraint::UnableToLock do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatAssignments::TeamConverterCommand.call(seat_assignment)
          end
        end
      end
    end

    test "doesn't run if seat assignment is pending cancellation" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      team = create(:team, organization: organization)
      team.add_member(user)

      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: team, pending_cancellation_date: Date.today)
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).never

      ActiveRecord::Base.connected_to(role: :reading) do
        assert_logged("Body" => "Skipping conversion of SeatAssignment because it is pending cancellation") do
          assert_raises(Copilot::Errors::SeatAssignmentPendingCancellationError) do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatAssignments::TeamConverterCommand.call(seat_assignment)
            end
          end
        end
      end
    end
  end

  context "child_teams" do
    test "without feature flag, handles child teams the same" do
      organization = create(:business_plus_organization)
      parent_team = create(:team, organization: organization, privacy: :closed)
      parent_user = create(:user)
      parent_team.add_member(parent_user)

      child_team = create(:team, organization: organization, parent_team_id: parent_team.id, privacy: :closed)
      child_user = create(:user)
      child_team.add_member(child_user)

      sub_child_team = create(:team, organization: organization, parent_team_id: child_team.id, privacy: :closed)
      sub_child_user = create(:user)
      sub_child_team.add_member(sub_child_user)

      team_seat_assignment = create(:copilot_seat_assignment, :team, assignable: parent_team, organization: organization)

      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization.id).once
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatAssignments::TeamConverterCommand.call(team_seat_assignment)
        end
      end
      assert_includes logs, "Feature flag disabled, loading members of this team only"
      assert_equal 1, Copilot::Seat.count
    end

    test "with feature flag, creates seats for child teams" do
      organization = create(:business_plus_organization)
      GitHub.flipper[:copilot_child_teams].enable(organization)
      parent_team = create(:team, organization: organization, privacy: :closed)
      parent_user = create(:user)
      parent_team.add_member(parent_user)

      child_team = create(:team, organization: organization, parent_team_id: parent_team.id, privacy: :closed)
      child_user = create(:user)
      child_team.add_member(child_user)

      sub_child_team = create(:team, organization: organization, parent_team_id: child_team.id, privacy: :closed)
      sub_child_user = create(:user)
      sub_child_team.add_member(sub_child_user)

      team_seat_assignment = create(:copilot_seat_assignment, :team, assignable: parent_team, organization: organization)

      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization.id).once
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatAssignments::TeamConverterCommand.call(team_seat_assignment)
        end
      end
      assert_includes logs, "Feature flag enabled, loading members of child teams"
      assert_includes logs, "Inserting seats"

      assert_equal 3, Copilot::Seat.count
    end
  end
end if GitHub.copilot_enabled?
