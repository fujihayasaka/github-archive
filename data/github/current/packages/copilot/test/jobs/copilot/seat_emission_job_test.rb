# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CopilotSeatEmissionJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "perform" do
    test "doesn't call subjob with flag disabled" do
      logs = capture_logs do
        Copilot::SeatEmissionJob.perform_now
      end
      assert_match "Skipping Copilot::SeatEmissionJob", logs
    end

    test "runs job" do
      GitHub.flipper[:copilot_seat_emission_job].enable
      logs = capture_logs do
        Copilot::SeatEmissionJob.perform_now
      end
      assert_match "Loading businesses and organizations for emission", logs
      assert_match "gh.copilot.seat_emission.organizations_count=\"0\"", logs
      assert_match "gh.copilot.seat_emission.businesses_count=\"0\"", logs
    end

    test "queues a single organization job" do
      GitHub.flipper[:copilot_seat_emission_job].enable

      seat = create(:copilot_seat, organization: create(:copilot_for_business_enabled_non_enterprise_organization))
      Copilot::Organization.new(seat.organization).enable_copilot!

      Copilot::Billing::OrganizationSeatEmissionJob.expects(:perform_later).with(seat.organization_id).once
      logs = capture_logs do
        Copilot::SeatEmissionJob.perform_now
      end
      assert_match "Starting Copilot seat emission job", logs
    end

    test "queues the different organization jobs" do
      GitHub.flipper[:copilot_seat_emission_job].enable

      seat = create(:copilot_seat, organization: create(:copilot_for_business_enabled_non_enterprise_organization))
      other_seat = create(:copilot_seat, organization: create(:copilot_for_business_enabled_non_enterprise_organization))

      Copilot::Organization.new(seat.organization).enable_copilot!
      Copilot::Organization.new(other_seat.organization).enable_copilot!

      Copilot::Billing::OrganizationSeatEmissionJob.expects(:perform_later).with(seat.organization_id).once
      Copilot::Billing::OrganizationSeatEmissionJob.expects(:perform_later).with(other_seat.organization_id).once
      logs = capture_logs do
        Copilot::SeatEmissionJob.perform_now
      end

      assert_match "Starting Copilot seat emission job", logs
    end

    test "queues a single job for an enterprise" do
      GitHub.flipper[:copilot_seat_emission_job].enable

      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)
      seat = create(:copilot_seat, organization: organization, assigned_user: user)

      Copilot::Billing::EnterpriseSeatEmissionJob.expects(:perform_later).with(seat.organization.business.id).once
      logs = capture_logs do
        Copilot::SeatEmissionJob.perform_now
      end
      assert_match "Starting Copilot seat emission job", logs
    end

    test "queues a single job for an enterprise with multiple orgs" do
      GitHub.flipper[:copilot_seat_emission_job].enable

      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)
      seat = create(:copilot_seat, organization: organization, assigned_user: user)

      other_organization = create(:copilot_for_business_enabled_organization, business: organization.business)
      other_user = create(:user)
      other_organization.add_member(other_user)
      create(:copilot_seat, organization: other_organization, assigned_user: other_user)

      Copilot::Billing::EnterpriseSeatEmissionJob.expects(:perform_later).with(seat.organization.business.id).once
      logs = capture_logs do
        Copilot::SeatEmissionJob.perform_now
      end
      assert_match "Starting Copilot seat emission job", logs
    end

    test "queues multiple jobs for enterprises" do
      GitHub.flipper[:copilot_seat_emission_job].enable

      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)
      seat = create(:copilot_seat, organization: organization, assigned_user: user)

      other_organization = create(:copilot_for_business_enabled_organization)
      other_user = create(:user)
      other_organization.add_member(other_user)
      other_seat = create(:copilot_seat, organization: other_organization, assigned_user: other_user)

      Copilot::Billing::EnterpriseSeatEmissionJob.expects(:perform_later).with(seat.organization.business.id).once
      Copilot::Billing::EnterpriseSeatEmissionJob.expects(:perform_later).with(other_seat.organization.business.id).once
      logs = capture_logs do
        Copilot::SeatEmissionJob.perform_now
      end
      assert_match "Starting Copilot seat emission job", logs
    end

    test "queues multiple jobs for enterprises and organizations" do
      GitHub.flipper[:copilot_seat_emission_job].enable

      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)
      seat = create(:copilot_seat, organization: organization, assigned_user: user)

      other_organization = create(:copilot_for_business_enabled_organization)
      other_user = create(:user)
      other_organization.add_member(other_user)
      other_seat = create(:copilot_seat, organization: other_organization, assigned_user: other_user)

      Copilot::Billing::EnterpriseSeatEmissionJob.expects(:perform_later).with(seat.organization.business.id).once
      Copilot::Billing::EnterpriseSeatEmissionJob.expects(:perform_later).with(other_seat.organization.business.id).once

      seat = create(:copilot_seat, organization: create(:organization)) # seat factory uses
      other_seat = create(:copilot_seat, organization: create(:organization))

      # TODO: Update this after standalone orgs can emit
      Copilot::Billing::OrganizationSeatEmissionJob.expects(:perform_later).with(seat.organization_id).never
      Copilot::Billing::OrganizationSeatEmissionJob.expects(:perform_later).with(other_seat.organization_id).never

      logs = capture_logs do
        Copilot::SeatEmissionJob.perform_now
      end

      assert_match "Starting Copilot seat emission job", logs
    end

    test "queues a single job for an enterprise team" do
      GitHub.flipper[:copilot_seat_emission_job].enable

      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      seat_assignment.convert_to_seats
      assert_equal 2, seat_assignment.seats.count

      Copilot::Billing::EnterpriseTeamEmissionJob.expects(:perform_later).with(seat_assignment.owner_id).once
      logs = capture_logs do
        Copilot::SeatEmissionJob.perform_now
      end
      assert_match "Starting Copilot seat emission job", logs
    end

    test "fails for disabled single organizations" do
      GitHub.flipper[:copilot_seat_emission_job].enable

      seat = create(:copilot_seat, organization: create(:copilot_for_business_enabled_non_enterprise_organization))
      Copilot::Organization.new(seat.organization).disable_copilot!

      Copilot::Billing::OrganizationSeatEmissionJob.expects(:perform_later).with(seat.organization_id).never
      logs = capture_logs do
        Copilot::SeatEmissionJob.perform_now
      end
      assert_match "Starting Copilot seat emission job", logs
    end
  end
end if GitHub.copilot_enabled?
