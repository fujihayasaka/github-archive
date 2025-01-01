# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::SeatManagement::OrganizationDeduplicateJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    GitHub.flipper[:copilot_organization_deduplicate_job].enable
  end

  context "perform" do
    test "resolves the tenant" do
      organization = create(:copilot_for_business_enabled_organization)

      on_multi_tenant_enterprise do
        Copilot::SeatManagement::OrganizationDeduplicateJob.perform_now(organization.id)
        assert_equal GitHub::CurrentTenant.get, organization.business
      end
    end

    test "does nothing if the organization has no seats" do
      organization = create(:organization)
      assert_no_changes -> { Copilot::Seat.count } do
        Copilot::SeatManagement::OrganizationDeduplicateJob.perform_now(organization.id)
      end
    end

    test "does nothing if the organization has a single non-duplicated seat" do
      seat = create(:copilot_seat)
      assert_no_changes -> { Copilot::Seat.count } do
        Copilot::SeatManagement::OrganizationDeduplicateJob.perform_now(seat.organization_id)
      end
    end

    test "does nothing if the organization has multiple non-duplicated seat" do
      seat = create(:copilot_seat)
      10.times do
        create(:copilot_seat, organization: seat.organization)
      end

      assert_no_changes -> { Copilot::Seat.count } do
        Copilot::SeatManagement::OrganizationDeduplicateJob.perform_now(seat.organization_id)
      end
    end

    test "removes single duplicated seat" do
      seat = create(:copilot_seat)
      team_assignment = create(:copilot_seat_assignment, :team, organization: seat.organization)
      team_assignment.assignable.add_member(seat.assigned_user)
      Copilot::Seat.create!(
        organization: seat.organization,
        assigned_user: seat.assigned_user,
        seat_assignment: team_assignment
      )

      assert_changes -> { Copilot::Seat.count }, from: 2, to: 1 do
        Copilot::SeatManagement::OrganizationDeduplicateJob.perform_now(seat.organization_id)
      end
    end

    test "removes multiple duplicated seats" do
      seat = create(:copilot_seat)
      organization = seat.organization
      team_assignment = create(:copilot_seat_assignment, :team, organization: organization)
      team_assignment.assignable.add_member(seat.assigned_user)
      Copilot::Seat.create!(
        organization: organization,
        assigned_user: seat.assigned_user,
        seat_assignment: team_assignment
      )

      5.times do
        other_seat = create(:copilot_seat, organization: organization)
        team_assignment = create(:copilot_seat_assignment, :team, organization: organization)
        team_assignment.assignable.add_member(other_seat.assigned_user)
        Copilot::Seat.create!(
          organization: organization,
          assigned_user: other_seat.assigned_user,
          seat_assignment: team_assignment
        )
      end

      assert_changes -> { Copilot::Seat.count }, from: 12, to: 6 do
        Copilot::SeatManagement::OrganizationDeduplicateJob.perform_now(organization.id)
      end
    end
  end
end if GitHub.copilot_enabled?
