# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::SeatAssignments::UserConverterCommandTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include DogstatsTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).never
  end

  context "initialize" do
    test "raises an error if the seat assignment is not a user" do
      assert_raises(Copilot::Errors::SeatAssignmentError) do
        assignment = create(:copilot_seat_assignment, :team)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatAssignments::UserConverterCommand.new(assignment)
        end
      end
    end
  end

  context "perform" do
    test "returns an existing seat if one exists" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)
      seat_assignment = create(:copilot_seat_assignment, :user, organization: organization, assignable: user)
      create(:copilot_seat, seat_assignment: seat_assignment, organization: organization, assigned_user: user)

      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization.id).once
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).never
      assert_no_difference "Copilot::Seat.count" do
        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "Found existing seat for this SeatAssignment") do
            Copilot::SeatAssignments::UserConverterCommand.call(seat_assignment)
          end
        end
      end
    end

    test "destroys any seats when suspended if one exists" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)
      seat_assignment = create(:copilot_seat_assignment, :user, organization: organization, assignable: user)
      create(:copilot_seat, seat_assignment: seat_assignment, organization: organization, assigned_user: user)

      user.update_column(:suspended_at, Time.now)

      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization.id).once
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).never
      assert_difference "Copilot::Seat.count", -1 do
        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "Found existing seat for this SeatAssignment") do
            Copilot::SeatAssignments::UserConverterCommand.call(seat_assignment)
          end
        end
      end
    end

    test "creates new seat if none exist" do
      organization = create(:organization)
      user = create(:user)
      organization.add_member(user)
      assert user.organizations.include?(organization)

      user_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user)

      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).with(organization.id).once
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).once
      assert_difference "Copilot::Seat.count", 1 do
        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "Creating new Seat for this User and Owner") do
            Copilot::SeatAssignments::UserConverterCommand.call(user_seat_assignment)
          end
        end
      end
    end

    test "doesn't create new seat if suspended" do
      organization = create(:organization)
      user = create(:user)
      organization.add_member(user)

      assert user.organizations.include?(organization)

      user_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user)
      user.update_column(:suspended_at, Time.now)

      Copilot::SeatManagement::OrganizationDeduplicateJob.expects(:perform_later).never
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).never
      assert_no_difference "Copilot::Seat.count" do
        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "User is suspended, not creating new seat") do
            Copilot::SeatAssignments::UserConverterCommand.call(user_seat_assignment)
          end
        end
      end
    end

    test "can't create a seat if they can't lock" do
      organization = create(:organization)
      user = create(:user)
      organization.add_member(user)
      assert user.organizations.include?(organization)

      user_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).never
      lock_key = "user-converter-command-#{organization.id}-#{user.id}"
      restraint = GitHub::Restraint.new

      restraint.lock!(lock_key, 1, 5.minutes) do
        assert_raises GitHub::Restraint::UnableToLock do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatAssignments::UserConverterCommand.call(user_seat_assignment)
          end
        end
      end
    end

    test "doesn't run if seat assignment is pending cancellation" do
      organization = create(:organization)
      user = create(:user)
      organization.add_member(user)

      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user, pending_cancellation_date: Date.today)
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).never

      ActiveRecord::Base.connected_to(role: :reading) do
        assert_logged("Body" => "Skipping conversion of SeatAssignment because it is pending cancellation") do
          assert_raises(Copilot::Errors::SeatAssignmentPendingCancellationError) do
            Copilot::SeatAssignments::UserConverterCommand.call(seat_assignment)
          end
        end
      end
    end

    test "destroys any seats for seat assignments pending cancellation in the past" do
      travel_to(DateTime.new(2023, 4, 1, 12, 0, 0)) do
        organization = create(:organization)
        user = create(:user)
        organization.add_member(user)

        seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user, pending_cancellation_date: Date.yesterday)
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).never

        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "SeatAssignment is pending cancellation and the date is in the past - destroying any seats") do
            assert_raises(Copilot::Errors::SeatAssignmentPendingCancellationError) do
              Copilot::SeatAssignments::UserConverterCommand.call(seat_assignment)
            end
          end
        end

        assert_equal 0, Copilot::Seat.where(seat_assignment: seat_assignment).count
        refute Copilot::SeatAssignment.exists?(seat_assignment.id)
      end
    end
  end
end if GitHub.copilot_enabled?
