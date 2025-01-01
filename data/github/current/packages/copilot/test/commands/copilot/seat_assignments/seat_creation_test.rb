# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotSeatAssignmentsSeatCreationTest < GitHub::TestCase
  include CopilotTestHelper

  Klass = Class.new do
    include Copilot::Helpers
    include Copilot::SeatAssignments::SeatCreation
  end

  context "ensure_convertible!" do
    test "raises an error if the assignment isn't for the converter type" do
      assert_raises(Copilot::Errors::SeatAssignmentError) do
        assignment = create(:copilot_seat_assignment, :organization)
        ActiveRecord::Base.connected_to(role: :reading) do
          Klass.new.ensure_convertible!(assignment, :ENTERPRISE_TEAM)
        end
      end
    end

    test "doesn't raise an error if the assignment is for the converter type" do
      assert_nothing_raised do
        assignment = create(:copilot_seat_assignment, :enterprise_team)
        ActiveRecord::Base.connected_to(role: :reading) do
          Klass.new.ensure_convertible!(assignment, :ENTERPRISE_TEAM)
        end
      end
    end

    test "raises an error if the assignment is for the wrong owner type" do
      other_business = create(:copilot_for_business_enabled_organization).business
      enterprise_team_seat_assignment = create(:copilot_seat_assignment, :enterprise_team)

      enterprise_team_seat_assignment.update_column(:owner_id, other_business.id)
      enterprise_team_seat_assignment.reload

      assert_equal other_business, enterprise_team_seat_assignment.owner
      assert_raises(Copilot::Errors::SeatAssignmentAssignableError) do
        ActiveRecord::Base.connected_to(role: :reading) do
          Klass.new.ensure_convertible!(enterprise_team_seat_assignment, :ENTERPRISE_TEAM)
        end
      end
    end

    test "doesn't raise an error if the assignment is for the right owner type" do
      assert_nothing_raised do
        assignment = create(:copilot_seat_assignment, :organization)
        ActiveRecord::Base.connected_to(role: :reading) do
          Klass.new.ensure_convertible!(assignment, :ORGANIZATION)
        end
      end

      assert_nothing_raised do
        assignment = create(:copilot_seat_assignment, :enterprise_team)
        ActiveRecord::Base.connected_to(role: :reading) do
          Klass.new.ensure_convertible!(assignment, :ENTERPRISE_TEAM)
        end
      end
    end

    test "doesn't convert assignment pending cancellation" do
      seat_assignment = create(:copilot_seat_assignment, :organization)
      seat_assignment.update_column(:pending_cancellation_date, 1.day.from_now)
      assert_raises(Copilot::Errors::SeatAssignmentPendingCancellationError) do
        ActiveRecord::Base.connected_to(role: :reading) do
          Klass.new.ensure_convertible!(seat_assignment, :ORGANIZATION)
        end
      end
      refute_nil Copilot::SeatAssignment.find_by(id: seat_assignment.id)
      assert_empty Copilot::Seat.where(copilot_seat_assignment_id: seat_assignment.id)
    end

    test "deletes a seat assignment that is pending cancellation in the past" do
      seat_assignment = create(:copilot_seat_assignment, :organization)
      seat_assignment.convert_to_seats
      refute_empty Copilot::Seat.where(copilot_seat_assignment_id: seat_assignment.id)
      seat_assignment.update_column(:pending_cancellation_date, 10.days.ago)
      assert_raises(Copilot::Errors::SeatAssignmentPendingCancellationError) do
        ActiveRecord::Base.connected_to(role: :reading) do
          Klass.new.ensure_convertible!(seat_assignment, :ORGANIZATION)
        end
      end
      assert_nil Copilot::SeatAssignment.find_by(id: seat_assignment.id)
      assert_empty Copilot::Seat.where(copilot_seat_assignment_id: seat_assignment.id)
    end
  end

  context "#insert_seats" do
    test "doesn't do anything for an empty array" do
      Copilot::ErrorReporter.expects(:report!).once
      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).never
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_added).never
      seats = []
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Klass.new.insert_seats(seats, Copilot::SeatAssignment.new)
        end
      end
      assert_includes logs, "No seats to insert"
    end

    test "creates seat records" do
      user = create(:user)
      organization = create(:copilot_for_business_enabled_organization)
      seat_assignment = create(:copilot_seat_assignment, :organization, organization: organization)
      seats = [
        {
          assigned_user_id: user.id,
          copilot_seat_assignment_id: seat_assignment.id,
          organization_id: organization.id,
        },
      ]
      ActiveRecord::Base.connected_to(role: :reading) do
        Klass.new.insert_seats(seats, seat_assignment)
      end

      assert_equal 1, Copilot::Seat.count

      seat = Copilot::Seat.first

      assert_equal user.id, seat.assigned_user_id
      assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
      assert_equal organization.id, seat.organization_id
    end

    test "starts a pending Copilot Business trial if there is one" do
      actor = create(:user)
      business_trial = create(:copilot_business_trial, :organization, state: :pending)
      organization = business_trial.trialable
      organization.add_member(actor)
      seat_assignment = create(:copilot_seat_assignment, :organization, assigning_user: actor, organization: organization)
      organization = business_trial.trialable
      seats = [
        assigned_user_id: 1,
        copilot_seat_assignment_id: 2,
        organization_id: organization.id
      ]

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_added).with(
        organization,
        seats.first[:assigned_user_id],
        actor,
        :batch_insert,
      )

      ActiveRecord::Base.connected_to(role: :reading) do
        Klass.new.insert_seats(seats, seat_assignment)
      end

      assert_equal "recently_started", business_trial.reload.state
    end

    test "starts a pending Copilot Enterprise trial if there is one and copilot_for_dotcom is enabled" do
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      actor = create(:user)
      organization = create(:organization, :enterprise_linked)
      organization.add_member(actor)
      seat_assignment = create(:copilot_seat_assignment, :organization, assigning_user: actor, organization: organization)
      trial = create(:copilot_business_trial, :organization,
        copilot_plan: "enterprise",
        state: "pending",
        trialable: organization,
      )
      seats = [
        assigned_user_id: 1,
        copilot_seat_assignment_id: 2,
        organization_id: organization.id
      ]

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_added).with(organization, 1, actor, :batch_insert)

      # Doing this instead of calling copilot_org.copilot_for_dotcom_enabled! since that would now trigger starting the CE trial
      create(:copilot_configuration, :organization, :copilot_for_dotcom_enabled, configurable: organization)

      ActiveRecord::Base.connected_to(role: :reading) do
        Klass.new.insert_seats(seats, seat_assignment)
      end

      assert_equal "recently_started", trial.reload.state
    end

    test "calls the SeatAssignedJob for each seat" do
      organization = create(:copilot_for_business_enabled_organization)
      seat_assignment = create(:copilot_seat_assignment, :organization, organization: organization)
      seats = [
        {
          assigned_user_id: 1,
          copilot_seat_assignment_id: seat_assignment.id,
          organization_id: organization.id,
        },
      ]

      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).with(organization.id, 1)
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_added).with(
        organization,
        seats.first[:assigned_user_id],
        seat_assignment.assigning_user,
        :batch_insert,
      )

      ActiveRecord::Base.connected_to(role: :reading) do
        Klass.new.insert_seats(seats, seat_assignment)
      end
    end

    test "calls the EnterpriseSeatAssignedJob for each seat" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      business = seat_assignment.owner
      seats = [
        {
          assigned_user_id: 1,
          copilot_seat_assignment_id: seat_assignment.id,
          organization_id: nil,
        },
      ]

      Copilot::SeatManagement::EnterpriseSeatAssignedJob.expects(:perform_later).with(business.id, 1)
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_added).with(
        business,
        seats.first[:assigned_user_id],
        seat_assignment.assigning_user,
        :batch_insert,
      )

      ActiveRecord::Base.connected_to(role: :reading) do
        Klass.new.insert_seats(seats, seat_assignment)
      end
    end

    test "does not emit organization start if we already have seats for this organization" do
      seat = create(:copilot_seat)
      seat_assignment = seat.seat_assignment
      organization = seat.organization
      seats = [
        {
          assigned_user_id: 1,
          copilot_seat_assignment_id: seat_assignment.id,
          organization_id: organization.id,
        },
      ]

      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).with(organization.id, 1)
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_added).with(
        organization,
        seats.first[:assigned_user_id],
        seat_assignment.assigning_user,
        :batch_insert,
      )

      ActiveRecord::Base.connected_to(role: :reading) do
        Klass.new.insert_seats(seats, seat_assignment)
      end
    end
  end
end if GitHub.copilot_enabled?
