# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::BusinessTrials::ExpirationJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include HydroTestHelpers

  setup do
    enable_feature_flag(:copilot_business_trial_job)
    disable_feature_flag(:copilot_for_enterprise)
  end

  context "perform" do
    test "it will do nothing if flag is disabled" do
      disable_feature_flag(:copilot_business_trial_job)
      organization = create(:organization)
      assert_logged("Body" => "Skipping Copilot::BusinessTrials::ExpirationJob") do
        Copilot::BusinessTrials::ExpirationJob.perform_now(organization.id)
      end
    end

    test "it cleans up seat assignments and disables the business when the Copilot Business trial ended" do
      freeze_time do
        business = create(:business)
        organization = create(:organization, business: business)
        user = create(:user)
        organization.add_member(user)
        staff = create(:staff_admin_user)
        trial = Copilot::BusinessTrial.create_trial!(organization, staff)
        trial.expired!
        seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user)
        seat_assignment.convert_to_seats

        Copilot::Business.any_instance.expects(:disable_copilot!).once
        Copilot::SeatManagement::SeatAssignmentCleanupJob.expects(:perform_later).with(seat_assignment.id, trial_seats: true).once

        Copilot::Instrumenter.expects(:instrument_copilot_business_trial_ended).with(organization).once

        assert_logged("Body" => "Kicking off SeatAssignmentCleanupJob", "gh.copilot.seat_assignment.id" => seat_assignment.id) do
          assert_logged("Body" => "Disabling Copilot for business", "gh.business.id" => business.id) do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::BusinessTrials::ExpirationJob.perform_now(organization.id)
            end
          end
        end
        assert seat_assignment.reload.pending_cancellation_today?
      end
    end

    test "it cleans up seat assignments and disables Copilot for the standalone organization when the Copilot Business trial ended" do
      freeze_time do
        organization = create(:organization)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(false)
        user = create(:user)
        organization.add_member(user)
        staff = create(:staff_admin_user)
        trial = Copilot::BusinessTrial.create_trial!(organization, staff)
        trial.expired!
        copilot_organization = Copilot::Organization.new(organization)
        copilot_organization.enable_copilot!
        copilot_organization.seat_management_selected_teams_and_users!
        seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user)
        seat_assignment.convert_to_seats

        Copilot::Organization.any_instance.expects(:disable_copilot!).once
        Copilot::SeatManagement::SeatAssignmentCleanupJob.expects(:perform_later).with(seat_assignment.id, trial_seats: true).once

        Copilot::Instrumenter.expects(:instrument_copilot_business_trial_ended).with(organization).once

        assert_logged("Body" => "Kicking off SeatAssignmentCleanupJob", "gh.copilot.seat_assignment.id" => seat_assignment.id) do
          assert_logged("Body" => "Disabling Copilot for trial organization", "gh.organization.id" => organization.id) do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::BusinessTrials::ExpirationJob.perform_now(organization.id)
            end
          end
        end

        assert seat_assignment.reload.pending_cancellation_today?
      end
    end

    test "it cleans up seat assignments but does not disable Copilot for the standalone organization when the organization has a valid payment method " do
      freeze_time do
        organization = create(:organization)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        user = create(:user)
        organization.add_member(user)
        staff = create(:staff_admin_user)
        trial = Copilot::BusinessTrial.create_trial!(organization, staff)
        trial.expired!
        copilot_organization = Copilot::Organization.new(organization)
        copilot_organization.enable_copilot!
        copilot_organization.seat_management_selected_teams_and_users!
        seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user)
        seat_assignment.convert_to_seats

        Copilot::Organization.any_instance.expects(:disable_copilot!).never
        Copilot::SeatManagement::SeatAssignmentCleanupJob.expects(:perform_later).with(seat_assignment.id, trial_seats: true).once

        Copilot::Instrumenter.expects(:instrument_copilot_business_trial_ended).with(organization).once

        assert_logged("Body" => "Kicking off SeatAssignmentCleanupJob", "gh.copilot.seat_assignment.id" => seat_assignment.id) do
          refute_logged("Body" => "Disabling Copilot for trial organization", "gh.organization.id" => organization.id) do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::BusinessTrials::ExpirationJob.perform_now(organization.id)
            end
          end
        end

        assert seat_assignment.reload.pending_cancellation_today?
        assert Copilot::Organization.new(organization.reload).seat_management_disabled?
      end
    end

    test "it disables Copilot only for the trial org if there are other orgs in the business with Copilot seats" do
      freeze_time do
        business = create(:business)
        organization = create(:organization, business: business)
        other_organization_with_seats = create(:organization, business: business)
        create(:copilot_seat, organization: other_organization_with_seats)

        user = create(:user)
        organization.add_member(user)
        staff = create(:staff_admin_user)
        trial = Copilot::BusinessTrial.create_trial!(organization, staff)
        trial.expired!
        seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user)
        seat_assignment.convert_to_seats

        Copilot::Business.any_instance.expects(:disable_copilot_for_selected_organizations!).with([organization.id]).once

        assert_logged("Body" => "Disabling Copilot for trial organization", "gh.organization.id" => organization.id) do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::BusinessTrials::ExpirationJob.perform_now(organization.id)
          end
        end
      end
    end

    test "it disables the Copilot Enterprise features but neither clean up seat assignments nor disable Copilot when the Copilot Enterprise trial ended" do
      freeze_time do
        business = create(:business)
        organization = create(:organization, business: business)
        user = create(:user)
        organization.add_member(user)
        staff = create(:staff_admin_user)

        # One of the requirements for the creation of Copilot Enterprise trials is that they must be Copilot billable
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        trial = Copilot::BusinessTrial.create_trial!(organization, staff, copilot_plan: "enterprise")

        seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user)
        seat_assignment.convert_to_seats

        refute Copilot::Organization.new(organization).copilot_for_dotcom_disabled?

        trial.update!(state: :expired)

        Copilot::Business.any_instance.expects(:disable_copilot!).never
        Copilot::SeatManagement::SeatAssignmentCleanupJob.expects(:perform_later).never

        Copilot::Instrumenter.expects(:instrument_copilot_business_trial_ended).with(organization).once

        perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::BusinessTrials::ExpirationJob.perform_now(organization.id)
          end
        end

        refute seat_assignment.reload.pending_cancellation_today?
        assert Copilot::Business.new(business).copilot_for_dotcom_disabled?
        assert Copilot::Organization.new(organization).copilot_for_dotcom_disabled?
      end
    end

    test "it returns early if business_trial is not expired" do
      freeze_time do
        business = create(:business)
        organization = create(:organization, business: business)
        user = create(:user)
        organization.add_member(user)
        staff = create(:staff_admin_user)

        trial = Copilot::BusinessTrial.create_trial!(organization, staff, copilot_plan: "enterprise")

        Copilot::Instrumenter.expects(:instrument_copilot_business_trial_ended).never

        assert_logged("Body" => "Business trial is not expired or canceled - skipping job", "gh.organization.id" => organization.id, "gh.copilot.business_trial.state" => trial.state) do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::BusinessTrials::ExpirationJob.perform_now(organization.id)
          end
        end
        refute Copilot::Business.new(business).copilot_for_dotcom_disabled?
        refute Copilot::Organization.new(organization).copilot_for_dotcom_disabled?
      end
    end

    test "resolves tenant on a multi-tenant enterprise with business owner" do
      on_multi_tenant_enterprise do
        # Simulate no tenant being set
        GitHub::CurrentTenant.remove
        assert_nil GitHub::CurrentTenant.get

        business = create(:business)
        organization = create(:organization, business: business)

        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::BusinessTrials::ExpirationJob.perform_now(organization.id)
        end

        assert_equal business, GitHub::CurrentTenant.get
      end
    end
  end
end if GitHub.copilot_enabled?
