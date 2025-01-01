# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::Billing::OrganizationSeatEmissionJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  include DogstatsTestHelpers

  setup do
    disable_feature_flag(:copilot_revokable_access)
  end

  context "flag" do
    test "doesn't call command with flag disabled" do
      disable_feature_flag(:skip_copilot_meuse_emission)
      Copilot::Billing::OrganizationSeatEmissionCommand.expects(:call).never
      logs = capture_logs do
        Copilot::Billing::OrganizationSeatEmissionJob.perform_now(1)
      end
      assert_match "Skipping Copilot::Billing::OrganizationSeatEmissionJob", logs
    end

    test "does emit seats with skip meuse flag enabled and prorated vNext billing" do
      enable_feature_flag(:copilot_revokable_access)

      Copilot::Organization.any_instance.stubs(:copilot_billable_result).returns({ billable: true, reason: :unknown })
      Copilot::Seat.any_instance.stubs(:can_emit_prorated_emission_billing_message?).returns(true)

      organization = create(:copilot_for_business_enabled_organization)

      seat = perform_enqueued_jobs(only: [Copilot::Billing::OrganizationAuthAndCaptureJob]) do
        create(:copilot_seat, organization: organization)
      end

      revoked_user = create(:user)
      organization.add_member(revoked_user)
      revoked_seat_assignment = Copilot::SeatAssignment.create!(
        owner_id: organization.id,
        owner_type: "Organization",
        assignable_type: "User",
        assignable_id: revoked_user.id,
        assigning_user: organization.admins.first
      )
      revoked_seat_assignment.convert_to_seats
      revoked_seat_assignment.unassign_and_revoke_access!(nil, :byeee)

      copilot_organization = Copilot::Organization.new(organization)
      business = organization.business
      enable_feature_flag(:copilot_seat_emission_job)
      enable_feature_flag(:skip_copilot_meuse_emission, business)

      assert copilot_organization.has_copilot_for_business?

      Copilot::Instrumenter.expects(:instrument_copilot_seat_emission_on_billing_platform).once

      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything).never

      logs = capture_logs do
        Copilot::Billing::OrganizationSeatEmissionJob.perform_now(seat.organization.id)
      end

      assert_match "Performing Copilot::Billing::OrganizationSeatEmissionJob", logs
      assert_match "Running SeatEmission Command", logs
      assert_match "Organization emits prorated emissions to billing platform", logs
      assert_includes logs, "Emitting prorated emission billing message"
      assert_includes logs, "user_id=\"#{revoked_user.id}\""
      assert_dogstats_increment 2, "copilot.billing_vnext.seat_prorated_emission"
    end

    test "doesn't call command with bad organization" do
      disable_feature_flag(:skip_copilot_meuse_emission)
      enable_feature_flag(:copilot_seat_emission_job)

      Copilot::ErrorReporter.expects(:report!).with do |error, extra_details|
        assert_instance_of Copilot::Errors::SeatEmissionOrganizationMissingError, error
        assert_equal "No organization found", error.message
        assert_equal 1, extra_details[:extra_details]["gh.organization.id"]
        assert_equal Set.new, extra_details[:extra_details]["gh.copilot.already_billed_user_ids"]
      end
      Copilot::Billing::OrganizationSeatEmissionCommand.expects(:call).never

      logs = capture_logs do
        Copilot::Billing::OrganizationSeatEmissionJob.perform_now(1)
      end

      assert_match "Performing Copilot::Billing::OrganizationSeatEmissionJob", logs
    end

    test "standalone orgs are cool" do
      disable_feature_flag(:skip_copilot_meuse_emission)
      enable_feature_flag(:copilot_seat_emission_job)

      Failbot.expects(:report).never
      organization = create(:organization)
      seat = create(:copilot_seat, organization: organization)

      Copilot::Billing::OrganizationSeatEmissionCommand.expects(:call).with(seat.organization, already_billed_user_ids: Set.new).returns(GitHub::Result.new { true })
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::Billing::OrganizationSeatEmissionJob.perform_now(seat.organization.id)
        end
      end
      assert_match "Running SeatEmission Command", logs
    end

    test "calls command with good organization" do
      disable_feature_flag(:skip_copilot_meuse_emission)
      enable_feature_flag(:copilot_seat_emission_job)

      Failbot.expects(:report).never
      organization = create(:copilot_for_business_enabled_organization)
      create(:copilot_seat, organization: organization)
      result = GitHub::Result.new { true }

      Copilot::Billing::OrganizationSeatEmissionCommand.expects(:call).with(organization, already_billed_user_ids: Set.new).returns(result)
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::Billing::OrganizationSeatEmissionJob.perform_now(organization.id)
        end
      end
      assert_match "Performing Copilot::Billing::OrganizationSeatEmissionJob", logs
      assert_match "Running SeatEmission Command", logs
    end

    test "run the job" do
      disable_feature_flag(:skip_copilot_meuse_emission)
      enable_feature_flag(:copilot_seat_emission_job)
      Copilot::Organization.any_instance.stubs(:copilot_billable_result).returns({ billable: true, reason: :unknown })
      enable_feature_flag(:copilot_revokable_access)

      organization = create(:copilot_for_business_enabled_organization)
      revoked_user = create(:user)
      organization.add_member(revoked_user)

      revoked_seat_assignment = Copilot::SeatAssignment.create!(
        owner_id: organization.id,
        owner_type: "Organization",
        assignable_type: "User",
        assignable_id: revoked_user.id,
        assigning_user: organization.admins.first
      )
      revoked_seat_assignment.convert_to_seats
      revoked_seat_assignment.unassign_and_revoke_access!(nil, :byeee)

      create(:copilot_seat, organization: organization)
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission).once
      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything)
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::Billing::OrganizationSeatEmissionJob.perform_now(organization.id)
        end
      end

      assert_match "Performing Copilot::Billing::OrganizationSeatEmissionJob", logs
      assert_match "Running SeatEmission Command", logs
      assert_includes logs, "gh.copilot.quantity=\"#{Copilot::Billing::Emittable.new(organization).per_seat_rate * 2}\""
    end

    test "doesn't run the job for standalone that has not enabled copilot" do
      disable_feature_flag(:skip_copilot_meuse_emission)
      enable_feature_flag(:copilot_seat_emission_job)

      organization = create(:credit_card_organization)

      seat = perform_enqueued_jobs(only: [Copilot::Billing::OrganizationAuthAndCaptureJob]) do
        create(:copilot_seat, organization: organization)
      end
      copilot_organization = Copilot::Organization.new(organization)

      refute copilot_organization.has_copilot_for_business?

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission_skipped).with(organization, "no_copilot_for_business").once

      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything).never
      GlobalInstrumenter.expects(:instrument).with("copilot.cfb_seat_cancelled", anything).once
      GlobalInstrumenter.expects(:instrument).with("copilot.access_revoked", { reason: "no_copilot_for_business", owner: organization, plan: "business" }).once

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::Billing::OrganizationSeatEmissionJob.perform_now(seat.organization.id)
        end
      end
      assert_match "Performing Copilot::Billing::OrganizationSeatEmissionJob", logs
      assert_match "Running SeatEmission Command", logs
    end

    test "run the job for standalone that has enabled copilot" do
      disable_feature_flag(:skip_copilot_meuse_emission)
      enable_feature_flag(:copilot_seat_emission_job)

      Copilot::Organization.any_instance.stubs(:copilot_billable_result).returns({ billable: true, reason: :unknown })

      organization = create(:organization)

      seat = perform_enqueued_jobs(only: [Copilot::Billing::OrganizationAuthAndCaptureJob]) do
        create(:copilot_seat, organization: organization)
      end

      copilot_organization = Copilot::Organization.new(organization)
      copilot_organization.enable_copilot!

      assert copilot_organization.has_copilot_for_business?
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission).once
      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything)
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::Billing::OrganizationSeatEmissionJob.perform_now(seat.organization.id)
        end
      end
      assert_match "Performing Copilot::Billing::OrganizationSeatEmissionJob", logs
      assert_match "Running SeatEmission Command", logs
    end

    test "resolved the context" do
      enable_feature_flag(:skip_copilot_meuse_emission)
      enable_feature_flag(:copilot_seat_emission_job)

      organization = create(:copilot_for_business_enabled_organization)

      on_multi_tenant_enterprise do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::Billing::OrganizationSeatEmissionJob.perform_now(organization.id)
        end
      end

      assert_equal GitHub::CurrentTenant.get, organization.business
    end
  end
end if GitHub.copilot_enabled?
