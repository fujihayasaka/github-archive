# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::Billing::OrganizationSeatEmissionCommandTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include DogstatsTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags
  include HydroTestHelpers

  setup do
    disable_feature_flag(:copilot_revokable_access)
  end

  context "perform" do
    test "doesn't run if it can't get a lock" do
      disable_feature_flag(:skip_copilot_meuse_emission)
      organization = create(:organization)

      lock_key = "org-seat-emission-command-#{organization.id}"
      restraint = GitHub::Restraint.new

      restraint.lock!(lock_key, 1, 5.minutes) do
        assert_raises GitHub::Restraint::UnableToLock do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::Billing::OrganizationSeatEmissionCommand.call(organization)
          end
        end
      end
    end

    test "doesn't work with organization not in cfb" do
      disable_feature_flag(:skip_copilot_meuse_emission)
      GitHub.logger.expects(:log).never

      organization = create(:business_organization)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission_skipped).with(
        organization,
        "no_seats"
      )

      assert_no_changes -> { Copilot::SeatEmission.count } do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::Billing::OrganizationSeatEmissionCommand.call(organization)
        end
      end
    end

    test "works for cfb with no previous emission" do
      disable_feature_flag(:skip_copilot_meuse_emission)
      Copilot::Organization.any_instance.stubs(:copilot_billable_result).returns({ billable: true, reason: :unknown })

      organization = create(:copilot_for_business_enabled_organization)

      create(:copilot_seat, organization: organization)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission).with(
        organization,
        instance_of(Copilot::SeatEmission),
        anything
      ).once
      Copilot::Billing::OrganizationSeatEmissionJob.expects(:perform_later).never

      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything)
      assert_difference -> { Copilot::SeatEmission.count }, 1 do
        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "Checking if organization can emit") do
            assert_logged("Body" => "Emitting seat emission", "gh.copilot.seats.count" => 1) do
              Copilot::Billing::OrganizationSeatEmissionCommand.call(organization)
            end
          end
        end
      end
    end

    test "works for cfb with previous emission older than a day" do
      disable_feature_flag(:skip_copilot_meuse_emission)
      Copilot::Organization.any_instance.stubs(:copilot_billable_result).returns({ billable: true, reason: :unknown })

      organization = create(:copilot_for_business_enabled_organization)

      create(:copilot_seat, organization: organization)

      create(:copilot_seat_emission, owner: organization, occurred_at: 20.days.ago)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission).once
      Copilot::Billing::OrganizationSeatEmissionJob.expects(:perform_later).never
      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything)

      assert_difference -> { Copilot::SeatEmission.count }, 1 do
        ActiveRecord::Base.connected_to(role: :reading) do
          logs = capture_logs do
            Copilot::Billing::OrganizationSeatEmissionCommand.call(organization)
          end
          assert_match "Checking if organization can emit", logs
          assert_match "Emitting seat emission", logs
        end
      end
    end

    test "creates zero-quantity SeatEmission but doesn't send to Meuse if all organization seats have been billed" do
      disable_feature_flag(:skip_copilot_meuse_emission)
      Copilot::Organization.any_instance.stubs(:copilot_billable_result).returns({ billable: true, reason: :unknown })

      organization = create(:copilot_for_business_enabled_organization)

      seat = create(:copilot_seat, organization: organization)

      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything).never
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission).never
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission_skipped).once

      assert_difference -> { Copilot::SeatEmission.count }, 1 do
        ActiveRecord::Base.connected_to(role: :reading) do
          logs = capture_logs do
            Copilot::Billing::OrganizationSeatEmissionCommand.call(organization, already_billed_user_ids: Set[seat.assigned_user_id])
          end
          assert_match "Checking if organization can emit", logs
          refute_match "Emitting seat emission", logs
          assert_match "Organization has no seats to emit", logs
          assert_match "Organization seats have all already been emitted", logs
        end
      end

      assert_equal 0, Copilot::SeatEmission.for_owner(organization).last&.quantity
    end

    test "creates SeatEmission and emits per-seat if customer is billed through Billing Platform with prorated emissions" do
      disable_feature_flag(:skip_copilot_meuse_emission)

      Copilot::Organization.any_instance.stubs(:copilot_billable_result).returns({ billable: true, reason: :unknown })

      organization = create(:copilot_for_business_enabled_organization)
      create :billing_platform_enabled_product, customer: organization.business.customer, copilot: true

      create(:copilot_seat, organization: organization)
      create(:copilot_seat, organization: organization)

      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything).never

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission).never
      Copilot::Instrumenter.expects(:instrument_copilot_seat_emission_on_billing_platform).once

      assert_difference -> { Copilot::SeatEmission.count }, 1 do
        ActiveRecord::Base.connected_to(role: :reading) do
          logs = capture_logs do
            Customer.stub_const(:BILLING_PLATFORM_COPILOT_ROLLOUT_DATE, Date.yesterday) do
              Copilot::Billing::OrganizationSeatEmissionCommand.call(organization)
            end
          end
          assert_match "Checking if organization can emit", logs
          assert_match "Emitting seat emission", logs
          assert_match "Emitting prorated emission billing message", logs

          assert_hydro_messages(schema: "billingplatform.v1.Usage", count: 2)
        end
      end
    end

    test "emits per-seat with the right sku" do
      disable_feature_flag(:skip_copilot_meuse_emission)
      Copilot::Organization.any_instance.stubs(:copilot_billable_result).returns({ billable: true, reason: :unknown })

      organization = create(:copilot_for_business_enabled_organization)
      create :billing_platform_enabled_product, customer: organization.business.customer, copilot: true

      Copilot::Organization.new(organization).copilot_plan_enterprise!
      create(:copilot_seat, organization: organization)
      create(:copilot_seat, organization: organization)

      assert_difference -> { Copilot::SeatEmission.count }, 1 do
        ActiveRecord::Base.connected_to(role: :reading) do
          capture_logs do
            Customer.stub_const(:BILLING_PLATFORM_COPILOT_ROLLOUT_DATE, Date.yesterday) do
              Copilot::Billing::OrganizationSeatEmissionCommand.call(organization)
            end
          end

          message = {
            sku: "copilot_enterprise"
          }
          assert_hydro_messages(schema: "billingplatform.v1.Usage", count: 2)
          assert_hydro_published_partial(message, schema: "billingplatform.v1.Usage")
        end
      end
    end

    test "exits for cfb with previous emission younger than a day" do
      disable_feature_flag(:skip_copilot_meuse_emission)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

      travel_to(DateTime.new(2023, 4, 1, 12, 0, 0)) do
        Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
        seat = create(:copilot_seat)
        organization = seat.seat_assignment.owner
        assert Copilot::Organization.new(organization).has_copilot_for_business?
        create(:copilot_seat, :organization, organization: organization)
        create(:copilot_seat_emission, owner: organization, occurred_at: 1.hour.ago)

        Copilot::Billing::OrganizationSeatEmissionJob.expects(:perform_later).never
        GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything).never

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission_skipped).with(organization, "too_soon").once
        logs = capture_logs do
          assert_no_changes -> { Copilot::SeatEmission.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::Billing::OrganizationSeatEmissionCommand.call(organization)
            end
          end
        end
        assert_includes logs, "Checking if organization can emit"
        assert_includes logs, "Organization cannot emit now"
      end
    end

    test "doesn't emit for organization in free flag" do
      disable_feature_flag(:skip_copilot_meuse_emission)
      GitHub.logger.stubs(:log).returns(true)
      organization = create(:copilot_for_business_enabled_free_organization)
      create(:copilot_seat, organization: organization)

      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything).never
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission_skipped).with(organization, "copilot_for_business_free").once
      assert_no_changes -> { Copilot::SeatEmission.count } do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::Billing::OrganizationSeatEmissionCommand.call(organization)
        end
      end
    end

    test "doesn't emit for spammy organizations and disables their copilot access" do
      disable_feature_flag(:skip_copilot_meuse_emission)
      GitHub.logger.stubs(:log).returns(true)
      organization = create(:copilot_for_business_enabled_organization)
      create(:copilot_seat, organization: organization)

      organization.mark_as_spammy

      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything).never
      GlobalInstrumenter.expects(:instrument).with("copilot.cfb_seat_cancelled", anything).once
      GlobalInstrumenter.expects(:instrument).with("copilot.access_revoked", { reason: "is_spammy", owner: organization, plan: "business" }).once
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission_skipped).with(organization, Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_spammy]).once

      assert_no_changes -> { Copilot::SeatEmission.count } do
        assert_changes -> { Copilot::Configuration.count + Copilot::SeatAssignment.count + Copilot::Seat.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::Billing::OrganizationSeatEmissionCommand.call(organization)
            organization.reload
          end
        end
      end
    end

    test "doesn't emit for deleted organizations" do
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      disable_feature_flag(:skip_copilot_meuse_emission)
      GitHub.logger.stubs(:log).returns(true)
      organization = create(:copilot_for_business_enabled_organization)
      create(:copilot_seat, organization: organization)

      organization.soft_delete!

      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything).never
      GlobalInstrumenter.expects(:instrument).with("copilot.cfb_seat_cancelled", anything).once
      GlobalInstrumenter.expects(:instrument).with("copilot.access_revoked", { reason: "is_deleted", owner: organization, plan: "business" }).once
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission_skipped).with(organization, Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_deleted]).once

      assert_no_changes -> { Copilot::SeatEmission.count } do
        assert_changes -> { Copilot::Configuration.count + Copilot::SeatAssignment.count + Copilot::Seat.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::Billing::OrganizationSeatEmissionCommand.call(organization)
          end
        end
      end
    end

    test "creates SeatEmission and emits per-seat for an enterprise-linked org with its own customer" do
      disable_feature_flag(:skip_copilot_meuse_emission)

      Copilot::Organization.any_instance.stubs(:copilot_billable_result).returns({ billable: true, reason: :unknown })
      Copilot::Organization.any_instance.stubs(:can_emit?).returns(true)

      # the business is billed via billing platform, this is the entity that should get picked up to check whether to emit
      business = create(:business)
      business.customer.update!(billed_via_billing_platform: true)

      # the org is not billed via billing platform, and has its own customer object
      organization = create(:copilot_for_business_enabled_organization, business: business)
      organization.customer = create(:customer, :zuora, billed_via_billing_platform: false)

      create :billing_platform_enabled_product, customer: organization.business.customer, copilot: true

      create(:copilot_seat, organization: organization)
      create(:copilot_seat, organization: organization)

      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage", anything).never

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission).never
      Copilot::Instrumenter.expects(:instrument_copilot_seat_emission_on_billing_platform).once

      assert_difference -> { Copilot::SeatEmission.count }, 1 do
        ActiveRecord::Base.connected_to(role: :reading) do
          logs = capture_logs do
            Customer.stub_const(:BILLING_PLATFORM_COPILOT_ROLLOUT_DATE, Date.yesterday) do
              Copilot::Billing::OrganizationSeatEmissionCommand.call(organization)
            end
          end
          assert_match "Checking if organization can emit", logs
          assert_match "Emitting seat emission", logs
          assert_match "Emitting prorated emission billing message", logs

          assert_hydro_messages(schema: "billingplatform.v1.Usage", count: 2)
        end
      end
    end
  end

end if GitHub.copilot_enabled?
