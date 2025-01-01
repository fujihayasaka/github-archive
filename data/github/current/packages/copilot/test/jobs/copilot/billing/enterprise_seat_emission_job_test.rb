# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::Billing::EnterpriseSeatEmissionJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    enable_feature_flag(:copilot_seat_emission_job)
    disable_feature_flag(:copilot_revokable_access)
  end

  context "copilot_seat_emission_job feature flag" do
    test "doesn't call command with flag disabled" do
      disable_feature_flag(:copilot_seat_emission_job)

      assert_logged("Body" => "Skipping Copilot::Billing::EnterpriseSeatEmissionJob") do
        Copilot::Billing::EnterpriseSeatEmissionJob.perform_now(1)
      end
    end

    test "doesn't call command with bad enterprise" do
      Copilot::ErrorReporter.expects(:report!).with do |error, context|
        error.is_a?(Copilot::Errors::CopilotError) &&
        context[:extra_details]["gh.business.id"] == 1
      end
      Copilot::Billing::EnterpriseSeatEmissionJob.perform_now(1)
    end

    test "full test" do
      disable_feature_flag(:skip_copilot_meuse_emission)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission).once

      organization = create(:copilot_for_business_enabled_organization)
      other_organization = create(:copilot_for_business_enabled_organization, business: organization.business)

      assert_equal other_organization.business.id, organization.business.id

      user = create(:user)
      organization.add_member(user)
      other_organization.add_member(user)

      Copilot::SeatAssignment.create!(
        organization: organization,
        assignable_id: user.id,
        assignable_type: "User",
        assigning_user_id: organization.admins.first.id,
      )
      Copilot::SeatAssignment.create!(
        organization: other_organization,
        assignable_id: user.id,
        assignable_type: "User",
        assigning_user_id: other_organization.admins.first.id,
      )

      assert_equal 2, Copilot::SeatAssignment.count

      Copilot::SeatAssignment.all.map(&:convert_to_seats)

      assert_equal 2, Copilot::Seat.count

      Copilot::Organization.any_instance.stubs(:copilot_billable_result).returns({ billable: true, reason: :unknown })

      assert_logged("Body" => "Emitting seat emission") do
        # this is because the user is in both orgs and deduped from the second)
        assert_logged("Body" => "Organization has no seats to emit") do
          assert_changes -> { Copilot::SeatEmission.count }, 1 do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::Billing::EnterpriseSeatEmissionJob.perform_now(organization.business.id)
            end
          end
        end
      end
    end

    test "full test with revoked access" do
      enable_feature_flag(:copilot_revokable_access)
      disable_feature_flag(:skip_copilot_meuse_emission)

      Copilot::Organization.any_instance.stubs(:copilot_billable_result).returns({ billable: true, reason: :unknown })

      organization = create(:copilot_for_business_enabled_organization)
      revoked_user = create(:user)
      organization.add_member(revoked_user)

      revokable_assignment = Copilot::SeatAssignment.create!(
        owner_id: organization.id,
        owner_type: "Organization",
        assignable_id: revoked_user.id,
        assignable_type: "User",
        assigning_user_id: organization.admins.first.id,
      )
      assert_equal 1, Copilot::SeatAssignment.count

      revokable_assignment.convert_to_seats
      revokable_assignment.unassign_and_revoke_access!(nil, :revoked)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_emission).once

      assert_logged("Body" => "Emitting seat emission") do
        # this is because the user is in both orgs and deduped from the second)
        refute_logged("Body" => "Organization has no seats to emit") do
          assert_changes -> { Copilot::SeatEmission.count }, 1 do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::Billing::EnterpriseSeatEmissionJob.perform_now(organization.business.id)
            end
          end
        end
      end
    end

    test "still emits if second organization has different seats" do
      organization = create(:copilot_for_business_enabled_organization)
      other_organization = create(:copilot_for_business_enabled_organization, business: organization.business)
      assert_equal other_organization.business.id, organization.business.id
      user = create(:user)
      organization.add_member(user)
      other_organization.add_member(user)

      Copilot::SeatAssignment.create!(
        organization: organization,
        assignable_id: user.id,
        assignable_type: "User",
        assigning_user_id: organization.admins.first.id,
      )
      Copilot::SeatAssignment.create!(
        organization: other_organization,
        assignable_id: user.id,
        assignable_type: "User",
        assigning_user_id: other_organization.admins.first.id,
      )

      create(:copilot_seat_assignment, :user, organization: other_organization)

      assert_equal 3, Copilot::SeatAssignment.count

      Copilot::SeatAssignment.all.map(&:convert_to_seats)

      assert_equal 3, Copilot::Seat.count

      Copilot::Organization.any_instance.stubs(:copilot_billable_result).returns({ billable: true, reason: :unknown })

      assert_logged("Body" => "Emitting seat emission") do
        assert_changes -> { Copilot::SeatEmission.count }, 2 do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::Billing::EnterpriseSeatEmissionJob.perform_now(organization.business.id)
          end
        end
      end
    end

    test "resolves tenant context" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)

      Copilot::SeatAssignment.create!(
        organization: organization,
        assignable_id: user.id,
        assignable_type: "User",
        assigning_user_id: organization.admins.first.id,
      )
      Copilot::SeatAssignment.all.map(&:convert_to_seats)

      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)

      on_multi_tenant_enterprise do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::Billing::EnterpriseSeatEmissionJob.perform_now(organization.business.id)
        end
      end

      assert_equal GitHub::CurrentTenant.get, organization.business
    end

    context "with customer onboarded to vNext" do
      test "prioritizes Copilot Business trial over Copilot Business" do
        business = create(:business)

        cb_org = create(:organization, business: business)

        cb_trial_org = create(:copilot_for_business_credit_card_enabled_organization, business: business)
        create(:copilot_business_trial, trialable_type: "Organization", trialable_id: cb_trial_org.id)
        create :billing_platform_enabled_product, customer: business.customer, copilot: true

        user = create(:user)
        cb_org.add_member(user)
        cb_trial_org.add_member(user)

        create(:copilot_seat, organization: cb_trial_org, assigned_user: user)
        create(:copilot_seat, organization: cb_org, assigned_user: user)
        assert_equal 2, Copilot::Seat.count

        Copilot::Organization.any_instance.stubs(:copilot_billable_result).returns({ billable: true, reason: :unknown })

        assert Copilot::SeatEmission.count.zero?

        assert_logged("Body" => "Organization cannot emit now, exiting") do
          assert_changes -> { Copilot::SeatEmission.count }, 1 do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::Billing::EnterpriseSeatEmissionJob.perform_now(business.id)
            end
          end
        end

        cb_org_trial_seat_emission = Copilot::SeatEmission.find_by(owner_type: "Organization", owner_id: cb_trial_org.id)
        cb_org_seat_emission = Copilot::SeatEmission.find_by(owner_type: "Organization", owner_id: cb_org.id)

        # CB org trial takes priority and the user's seat is attributed to it. However, CB trials do not emit
        refute cb_org_trial_seat_emission

        # CB org seat emission should have 0.0 seat count as the user's seat was already accounted for in the CB org trial
        assert_equal 0.0, T.must(cb_org_seat_emission).emission["seat_count"]
      end
    end

    test "prioritizes the org with a higher SKU" do
      cb_org = create(:copilot_for_business_enabled_organization)
      business = cb_org.business
      ce_org = create(:copilot_for_business_enabled_organization, business: business)
      Copilot::Organization.new(ce_org).copilot_plan_enterprise!
      create(:billing_sales_serve_plan_subscription, customer: business.customer)
      create :billing_platform_enabled_product, customer: business.customer, copilot: false

      user = create(:user)
      cb_org.add_member(user)
      ce_org.add_member(user)

      create(:copilot_seat, organization: cb_org, assigned_user: user)
      create(:copilot_seat, organization: ce_org, assigned_user: user)
      assert_equal 2, Copilot::Seat.count

      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

      assert Copilot::SeatEmission.count.zero?

      assert_logged("Body" => "Emitting seat emission") do
        assert_changes -> { Copilot::SeatEmission.count }, 1 do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::Billing::EnterpriseSeatEmissionJob.perform_now(business.id)
          end
        end
      end

      # There will be seat emissions captured for both, but seat_count should go to the higher ARR SKU
      assert_equal 2, Copilot::SeatEmission.count

      cb_org_seat_emission = Copilot::SeatEmission.find_by(owner_type: "Organization", owner_id: cb_org.id)
      ce_org_seat_emission = Copilot::SeatEmission.find_by(owner_type: "Organization", owner_id: ce_org.id)

      # CB org seat emission should have 0.0 seat count, CE org seat emission should have 1.0 seat count
      assert_equal 0.0, T.must(cb_org_seat_emission).emission["seat_count"]
      assert_equal 1.0, T.must(ce_org_seat_emission).emission["seat_count"]
    end
  end
end if GitHub.copilot_enabled?
