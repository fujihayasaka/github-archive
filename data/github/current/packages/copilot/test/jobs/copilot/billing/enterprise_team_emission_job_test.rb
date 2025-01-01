# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::Billing::EnterpriseTeamEmissionJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  include HydroTestHelpers
  include DogstatsTestHelpers

  setup do
    enable_feature_flag(:copilot_seat_emission_job)
    disable_feature_flag(:copilot_revokable_access)
    disable_feature_flag(:skip_copilot_meuse_emission)
  end

  context "flag" do
    test "doesn't call command with flag disabled" do
      disable_feature_flag(:copilot_seat_emission_job)

      assert_logged("Body" => "Skipping Copilot::Billing::EnterpriseTeamEmissionJob") do
        Copilot::Billing::EnterpriseTeamEmissionJob.perform_now(1)
      end
    end

    test "doesn't call command with bad enterprise" do
      Copilot::ErrorReporter.expects(:report!).with do |error, context|
        error.is_a?(Copilot::Errors::CopilotError) &&
        context[:extra_details]["gh.business.id"] == 1
      end
      Copilot::Billing::EnterpriseTeamEmissionJob.perform_now(1)
    end

    test "does nothing if the business has no seats" do
      business = create(:business)
      assert_equal 0, Copilot::Seat.count
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission_skipped).once
      logs = capture_logs do
        Copilot::Billing::EnterpriseTeamEmissionJob.perform_now(business.id)
      end
      assert_includes logs, "Enterprise has no seats to emit"
    end

    test "does nothing if the business has emitted recently" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      seat_assignment.convert_to_seats
      business = seat_assignment.owner
      assert_equal 2, Copilot::Seat.count
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission_skipped).once
      travel_to(Time.new(2020, 1, 1, 12, 0, 0, 0)) do # 12 because the db still loves PST
        create(:copilot_seat_emission, owner: business, occurred_at: 1.hour.ago)
        logs = capture_logs do
          Copilot::Billing::EnterpriseTeamEmissionJob.perform_now(business.id)
        end
        assert_includes logs, "Enterprise has seats to emit"
        assert_includes logs, "Enterprise cannot emit now, exiting"
      end
    end

    test "emits meuse payload if the business is cool" do
      enable_feature_flag(:copilot_revokable_access)

      travel_to(Time.new(2020, 1, 1, 12, 0, 0, 0)) do # 12 because the db still loves PST
        seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
        seat_assignment.convert_to_seats
        seat_assignment.unassign_and_revoke_access!(nil, :byee, force: true)

        business = seat_assignment.owner
        assert_equal 2, Copilot::Seat.count

        Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)
        Copilot::Business.any_instance.stubs(:copilot_disabled?).returns(false)

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission).once
        GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything)

        logs = capture_logs do
          assert_changes -> { Copilot::SeatEmission.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::Billing::EnterpriseTeamEmissionJob.perform_now(business.id)
            end
          end
        end
        assert_includes logs, "Enterprise has seats to emit"
        assert_includes logs, "Emitting seat emission"
        assert_includes logs, "gh.copilot.quantity=\"#{Copilot::Billing::Emittable.new(business).per_seat_rate * 2}\""
      end
    end

    test "emits to the Copilot Standalone SKU on the billing platform" do
      enable_feature_flag(:skip_copilot_meuse_emission)
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      seat_assignment.convert_to_seats
      business = seat_assignment.owner
      create(:billing_platform_enabled_product, customer: business.customer, copilot: true)

      seat_assignment_two = create(:copilot_seat_assignment, :enterprise_team)
      seat_assignment_two.convert_to_seats
      business_two = seat_assignment_two.owner
      create(:billing_platform_enabled_product, customer: business_two.customer, copilot: true)
      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)
      Copilot::Business.any_instance.stubs(:copilot_disabled?).returns(false)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission).never
      Copilot::Instrumenter.expects(:instrument_copilot_seat_emission_on_billing_platform).twice
      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything).never
      travel_to(Time.new(2020, 1, 1, 12, 0, 0, 0)) do # 12 because the db still loves PST
        logs = capture_logs do
          assert_changes -> { Copilot::SeatEmission.count } do
            Customer.stub_const(:BILLING_PLATFORM_COPILOT_ROLLOUT_DATE, Date.yesterday) do
              Copilot::Billing::EnterpriseTeamEmissionJob.perform_now(business.reload.id)
            end
          end
          assert_changes -> { Copilot::SeatEmission.count } do
            Customer.stub_const(:BILLING_PLATFORM_COPILOT_ROLLOUT_DATE, Date.yesterday) do
              Copilot::Billing::EnterpriseTeamEmissionJob.perform_now(business_two.reload.id)
            end
          end
        end
        assert_includes logs, "Enterprise has seats to emit"
        assert_includes logs, "Emitting seat emission"
        message = {
          sku: "copilot_standalone"
        }

        assert_hydro_messages(schema: "billingplatform.v1.Usage", count: 4)
        assert_hydro_published_partial(message, schema: "billingplatform.v1.Usage")
      end
    end

    test "does not emit to the Copilot Standalone SKU on the billing platform if the extra sku feature flag is disabled" do
      enable_feature_flag(:skip_copilot_meuse_emission)
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      seat_assignment.convert_to_seats
      business = seat_assignment.owner
      create(:billing_platform_enabled_product, customer: business.customer, copilot: true)

      seat_assignment_two = create(:copilot_seat_assignment, :enterprise_team)
      seat_assignment_two.convert_to_seats
      business_two = seat_assignment_two.owner
      create(:billing_platform_enabled_product, customer: business_two.customer, copilot: true)
      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)
      Copilot::Business.any_instance.stubs(:copilot_disabled?).returns(false)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission).twice
      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything).twice
      travel_to(Time.new(2020, 1, 1, 12, 0, 0, 0)) do # 12 because the db still loves PST
        logs = capture_logs do
          assert_changes -> { Copilot::SeatEmission.count } do
            Copilot::Billing::EnterpriseTeamEmissionJob.perform_now(business.reload.id)
          end
          assert_changes -> { Copilot::SeatEmission.count } do
            Copilot::Billing::EnterpriseTeamEmissionJob.perform_now(business_two.reload.id)
          end
        end
        assert_includes logs, "Enterprise has seats to emit"
        assert_includes logs, "Emitting seat emission"

        refute_hydro_messages(schema: "billingplatform.v1.Usage")
      end
    end

    test "does not interfere with other enterprise team emissions" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      seat_assignment.convert_to_seats
      business = seat_assignment.owner
      assert_equal 2, Copilot::Seat.count

      seat_assignment_two = create(:copilot_seat_assignment, :enterprise_team)
      seat_assignment_two.convert_to_seats
      business_two = seat_assignment_two.owner
      assert_equal 4, Copilot::Seat.count

      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)
      Copilot::Business.any_instance.stubs(:copilot_disabled?).returns(false)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission).twice
      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything).twice
      travel_to(Time.new(2020, 1, 1, 12, 0, 0, 0)) do # 12 because the db still loves PST
        logs = capture_logs do
          assert_changes -> { Copilot::SeatEmission.count } do
            Copilot::Billing::EnterpriseTeamEmissionJob.perform_now(business.id)
          end
          assert_changes -> { Copilot::SeatEmission.count } do
            Copilot::Billing::EnterpriseTeamEmissionJob.perform_now(business_two.id)
          end
        end
        assert_includes logs, "Enterprise has seats to emit"
        assert_includes logs, "Emitting seat emission"
      end
    end

    test "will log if copilot is disabled" do
      disable_feature_flag(:copilot_revokable_access)

      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      seat_assignment.convert_to_seats
      business = seat_assignment.owner

      Copilot::Business.any_instance.stubs(:copilot_billable_result).returns({ billable: true, reason: :unknown })
      Copilot::Business.any_instance.stubs(:copilot_disabled?).returns(true)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission).never

      travel_to(Time.new(2020, 1, 1, 12, 0, 0, 0)) do # 12 because the db still loves PST
        logs = capture_logs do
          assert_no_changes -> { Copilot::SeatEmission.count } do
            Copilot::Billing::EnterpriseTeamEmissionJob.perform_now(business.id)
          end
        end
        assert_includes logs, "Enterprise cannot emit now, exiting"
        assert_includes logs, Copilot::COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business]
      end
    end

    context "failed to emit logging" do
      test "logs when a business is spammy" do
        copilot_business = build_business
        Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)

        copilot_business.business_object.mark_as_spammy

        reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_spammy]
        Copilot::Instrumenter
          .expects(:instrument_copilot_for_business_seat_emission_skipped)
          .with(copilot_business.business_object, reason)
          .once
        Copilot::Billing::EnterpriseTeamEmissionJob.perform_now(copilot_business.id)
      end

      test "logs when a business is suspended" do
        copilot_business = build_business
        business = copilot_business.business_object
        Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)

        business.suspend("bad dudes")

        reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_suspended]
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission_skipped).with(business, reason).once
        Copilot::Billing::EnterpriseTeamEmissionJob.perform_now(business.id)
      end

      test "logs when copilot is disabled for business" do
        disable_feature_flag(:copilot_revokable_access)

        ::Business.any_instance.stubs(:metered_services_billable?).returns({ billable: true, reason: :unknown })
        Copilot::Business.any_instance.stubs(:copilot_billable_result).returns({ billable: true, reason: :unknown })

        copilot_business = build_business
        copilot_business.disable_copilot!

        Copilot::Instrumenter
          .expects(:instrument_copilot_for_business_seat_emission_skipped)
          .with(copilot_business.business_object, Copilot::COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business])
          .once

        Copilot::EnterpriseCleaner
          .expects(:call)
          .once
        Copilot::Billing::EnterpriseTeamEmissionJob.perform_now(copilot_business.id)
        assert_dogstats_increment("copilot.seat_emission.cannot_emit", tags: ["type:enterprise", "reason:no_copilot_for_business"])
      end
    end

    test "resolves the tenant" do
      biz = build_business.business_object

      on_multi_tenant_enterprise do
        Copilot::Billing::EnterpriseTeamEmissionJob.perform_now(biz.id)
      end

      assert_equal GitHub::CurrentTenant.get, biz
    end
  end

  sig { returns(Copilot::Business) }
  def build_business
    seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    seat_assignment.convert_to_seats
    business = seat_assignment.owner
    copilot_biz = Copilot::Business.new(business)
    copilot_biz.enable_copilot!

    copilot_biz
  end
end if GitHub.copilot_enabled?
