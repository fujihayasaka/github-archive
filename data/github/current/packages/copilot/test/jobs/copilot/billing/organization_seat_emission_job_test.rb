# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::Billing::OrganizationSeatEmissionJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "flag" do
    test "doesn't call command with flag disabled" do
      GitHub.flipper[:skip_copilot_meuse_emission].disable
      Copilot::Billing::OrganizationSeatEmissionCommand.expects(:call).never
      logs = capture_logs do
        Copilot::Billing::OrganizationSeatEmissionJob.perform_now(1)
      end
      assert_match "Skipping Copilot::Billing::OrganizationSeatEmissionJob", logs
    end

    test "does emit seats with skip meuse flag enabled and prorated vNext billing" do
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      organization = create(:copilot_for_business_enabled_organization)

      seat = perform_enqueued_jobs(only: [Copilot::Billing::OrganizationAuthAndCaptureJob]) do
        create(:copilot_seat, organization: organization)
      end

      copilot_organization = Copilot::Organization.new(organization)
      business = organization.business
      GitHub.flipper[:copilot_seat_emission_job].enable
      GitHub.flipper[:skip_copilot_meuse_emission].enable(business)

      assert copilot_organization.has_copilot_for_business?

      Copilot::Instrumenter.expects(:instrument_copilot_seat_emission_on_billing_platform).once

      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything).never

      logs = capture_logs do
        Copilot::Billing::OrganizationSeatEmissionJob.perform_now(seat.organization.id)
      end
      assert_match "Performing Copilot::Billing::OrganizationSeatEmissionJob", logs
      assert_match "Running SeatEmission Command", logs
      assert_match "Organization emits prorated emissions to billing platform", logs
    end

    test "doesn't call command with bad organization" do
      GitHub.flipper[:skip_copilot_meuse_emission].disable
      GitHub.flipper[:copilot_seat_emission_job].enable

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
      GitHub.flipper[:skip_copilot_meuse_emission].disable
      GitHub.flipper[:copilot_seat_emission_job].enable
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
      GitHub.flipper[:skip_copilot_meuse_emission].disable
      GitHub.flipper[:copilot_seat_emission_job].enable
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
      GitHub.flipper[:skip_copilot_meuse_emission].disable
      GitHub.flipper[:copilot_seat_emission_job].enable
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

      organization = create(:copilot_for_business_enabled_organization)
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
    end

    test "doesn't run the job for standalone that has not enabled copilot" do
      GitHub.flipper[:skip_copilot_meuse_emission].disable
      GitHub.flipper[:copilot_seat_emission_job].enable

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
      GitHub.flipper[:skip_copilot_meuse_emission].disable
      GitHub.flipper[:copilot_seat_emission_job].enable

      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

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
      GitHub.flipper[:copilot_seat_emission_job].enable
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
