# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/missing_record_helper"

class Copilot::SeatManagement::OrganizationJobTest < GitHub::TestCase
  include CopilotTestHelper
  include JobTestHelper
  include MissingRecordHelper
  include GitHub::LoggerHelper

  setup do
    GitHub.flipper[:copilot_seat_assignment_job].enable
  end

  test "invalid action" do
    assert_raises ArgumentError do
      Copilot::SeatManagement::OrganizationJob.perform_now(
        action: :invalid,
        organization_id: 0,
        customer_id: 1,
      )
    end
  end

  context "#organization_archived" do
    context "without seats or seat assignments" do
      test "does not raise an error" do
        org = create(:organization)
        org.delete

        assert_nothing_raised do
          assert_logged(
            "code.namespace" => "Copilot::SeatManagement::OrganizationJob",
            "code.function" => "perform",
            "gh.org.id" => org.id,
          ) do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationJob.perform_now(
                action: :organization_archived,
                organization_id: org.id,
                customer_id: 1,
              )
            end
          end
        end
      end
    end

    context "with seats and seat assignments" do
      test "cancels seats and destroys seat assignments" do
        org = create(:copilot_for_business_enabled_organization)
        customer = Copilot::Organization.new(org).customer_for
        user = create(:user)
        team = create(:team, organization: org)
        team.add_member(user)

        seat_assignment = create(
          :copilot_seat_assignment,
          :team,
          assignable: team,
          organization: org,
        )
        seat_assignment.convert_to_seats
        seat = seat_assignment.seats.first
        assert seat
        seat.reload
        assert seat.organization.present?
        org_id = org.id
        org.destroy!

        assert_logged("Body" => "Destroying seat") do
          assert_logged("Body" => "Destroying seat assignment") do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationJob.perform_now(
                action: :organization_archived,
                organization_id: org.id,
                customer_id: T.must(customer).id,
              )
            end
          end
        end

        refute Copilot::Seat.exists?(seat.id),
          "deletes the seat"
        refute Copilot::SeatAssignment.exists?(seat_assignment.id),
          "deletes the seat assignment"
        refute Copilot::Configuration.exists?(configurable_type: "Organization", configurable_id: org_id),
          "deletes the configuration"
      end
    end
  end

  context "#organization_suspended" do
    context "without seats or seat assignments" do
      test "does not raise an error" do
        org = create(:organization)
        org.suspend("suspension reason", send_email: false)


        assert_nothing_raised do
          assert_logged(
            "code.namespace" => "Copilot::SeatManagement::OrganizationJob",
            "code.function" => "perform",
            "gh.org.id" => org.id,
          ) do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationJob.perform_now(
                action: :organization_suspended,
                organization_id: org.id,
                customer_id: 1,
              )
            end
          end
        end
      end
    end

    context "with seats and seat assignments" do
      test "cancels seats and destroys seat assignments" do
        org = create(:copilot_for_business_enabled_organization)
        customer = T.must(Copilot::Organization.new(org).customer_for)
        user = create(:user)
        team = create(:team, organization: org)
        team.add_member(user)

        seat_assignment = create(
          :copilot_seat_assignment,
          :team,
          assignable: team,
          organization: org,
        )
        seat_assignment.convert_to_seats
        seat = seat_assignment.seats.first
        assert seat
        seat.reload
        assert seat.organization.present?
        org_id = org.id
        org.suspend("suspension reason", send_email: false)

        assert_logged("Body" => "Destroying seat") do
          assert_logged("Body" => "Destroying seat assignment") do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationJob.perform_now(
                action: :organization_suspended,
                organization_id: org.id,
                customer_id: customer.id,
              )
            end
          end
        end

        refute Copilot::Seat.exists?(seat.id),
          "deletes the seat"
        refute Copilot::SeatAssignment.exists?(seat_assignment.id),
          "deletes the seat assignment"
        refute Copilot::Configuration.exists?(configurable_type: "Organization", configurable_id: org_id),
          "deletes the configuration"
      end
    end
  end

  context "#organization_destroyed" do
    context "without seats or seat assignments" do
      test "does not raise an error" do
        org = create(:organization)
        org.delete


        assert_nothing_raised do
          assert_logged(
            "code.namespace" => "Copilot::SeatManagement::OrganizationJob",
            "code.function" => "perform",
            "gh.org.id" => org.id,
          ) do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationJob.perform_now(
                action: :organization_destroyed,
                organization_id: org.id,
                customer_id: 1,
              )
            end
          end
        end
      end
    end

    context "with seats and seat assignments" do
      test "cancels seats and destroys seat assignments" do
        org = create(:copilot_for_business_enabled_organization)
        customer = T.must(Copilot::Organization.new(org).customer_for)
        user = create(:user)
        team = create(:team, organization: org)
        team.add_member(user)

        seat_assignment = create(
          :copilot_seat_assignment,
          :team,
          assignable: team,
          organization: org,
        )
        seat_assignment.convert_to_seats
        seat = seat_assignment.seats.first
        assert seat
        seat.reload
        assert seat.organization.present?
        org_id = org.id
        org.destroy!

        assert_logged("Body" => "Destroying seat") do
          assert_logged("Body" => "Destroying seat assignment") do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationJob.perform_now(
                action: :organization_destroyed,
                organization_id: org.id,
                customer_id: customer.id,
              )
            end
          end
        end

        refute Copilot::Seat.exists?(seat.id),
          "deletes the seat"
        refute Copilot::SeatAssignment.exists?(seat_assignment.id),
          "deletes the seat assignment"
        refute Copilot::Configuration.exists?(configurable_type: "Organization", configurable_id: org_id),
          "deletes the configuration"
      end
    end
  end
end if GitHub.copilot_enabled?
