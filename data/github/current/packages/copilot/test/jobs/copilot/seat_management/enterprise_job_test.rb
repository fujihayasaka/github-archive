# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::SeatManagement::EnterpriseJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  include HydroTestHelpers

  context "perform" do
    test "raises an error if the action is invalid" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      action = :invalid_action

      assert_raises(ArgumentError) do
        Copilot::SeatManagement::EnterpriseJob.perform_now(
          organization_id: organization.id,
          enterprise_id: organization.business.id,
          action: action,
          transaction_id: "1234",
          payload: { foo: "bar" },
          actor_id: user.id,
        )
      end
    end

    test "does nothing with fake org" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      action = :remove_organization

      Copilot::ErrorReporter.expects(:report!).with do |error, context|
        error.is_a?(Copilot::Errors::CopilotError) &&
        context[:extra_details]["gh.organization.id"] == 233552342 # fake org id
      end

      assert_logged("Body" => "Invalid Organization") do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseJob.perform_now(
            organization_id: 233552342,
            enterprise_id: organization.business.id,
            action: action,
            transaction_id: "1234",
            payload: { foo: "bar" },
            actor_id: user.id,
          )
        end
      end
    end

    test "does nothing with fake enterprise" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      action = :remove_organization

      assert_logged("Body" => "Invalid Enterprise") do
        Copilot::ErrorReporter.expects(:report!).with do |error, context|
          error.is_a?(Copilot::Errors::CopilotError) &&
          context[:extra_details]["gh.organization.id"] == organization.id &&
          context[:extra_details]["gh.business.id"] == 233552342
        end
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseJob.perform_now(
            organization_id: organization.id,
            enterprise_id: 233552342,
            action: action,
            transaction_id: "1234",
            payload: { foo: "bar" },
            actor_id: user.id,
          )
        end
      end
    end
  end

  context "add_organization" do
    test "sets existing organization Copilot policies to the enterprise's Copilot policies" do
      organization = create(:copilot_for_business_enabled_non_enterprise_organization)

      user = create(:user)
      organization.add_member(user)
      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user, assigning_user: organization.admins.first)
      create(:copilot_seat, organization: organization, assigned_user: user, seat_assignment: seat_assignment)

      copilot_organization = Copilot::Organization.new(organization)

      copilot_organization.block_public_code_suggestions!
      copilot_organization.disable_chat!

      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      copilot_business.enable_chat!
      copilot_business.allow_public_code_suggestions!

      assert copilot_business.chat_enabled?

      mailer = mock
      mailer.stubs(:deliver_later)

      # no one should get an email about chat settings
      CopilotForBusinessMailer
      .expects(:chat_enabled_for_user)
      .returns(mailer)
      .never

      business.add_organization(organization)

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::EnterpriseJob.perform_now(
          organization_id: organization.id,
          enterprise_id: business.id,
          action: :add_organization,
          transaction_id: "1234",
          payload: { foo: "bar" },
          actor_id: organization.admins.first.id,
        )
      end

      assert Copilot::Organization.new(organization).chat_enabled?
      assert Copilot::Organization.new(organization).allow_public_code_suggestions?
    end

    test "cancels existing organization seat assignments if the enterprise has CfB disabled for all orgs" do
      organization = create(:copilot_for_business_enabled_non_enterprise_organization)
      user = create(:user)
      organization.add_member(user)
      user_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user, assigning_user: organization.admins.first)
      user_seat_assignment.convert_to_seats

      copilot_organization = Copilot::Organization.new(organization)
      copilot_organization.seat_management_allow_all!

      assert_nil user_seat_assignment.pending_cancellation_date

      business = create(:business)
      business.add_organization(organization)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_management_changed).once.with(nil, organization, "enabled_for_all", "disabled")

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseJob.perform_now(
            organization_id: organization.id,
            enterprise_id: business.id,
            action: :add_organization,
            transaction_id: "1234",
            payload: { foo: "bar" },
            actor_id: organization.admins.first.id,
          )
        end
      end

      assert_match "Enterprise has Copilot fully disabled, disabling org's seats", logs
      assert_match "seat_management_disable!", logs
      assert_nil Copilot::SeatAssignment.find_by(assignable_type: "User", assignable_id: user.id)
      organization_seat = Copilot::SeatAssignment.find_by(assignable_type: "Organization", assignable_id: organization.id)
      refute_nil organization_seat
      refute_nil organization_seat&.pending_cancellation_date

      organization.reload
    end

    test "retains existing organization seat assignments if the enterprise has CfB enabled for selected orgs" do
      organization = create(:copilot_for_business_enabled_non_enterprise_organization)
      user = create(:user)
      organization.add_member(user)
      user_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user, assigning_user: organization.admins.first)
      user_seat_assignment.convert_to_seats

      assert_nil user_seat_assignment.pending_cancellation_date

      business = create(:business)
      Copilot::Business.new(business).enable_copilot_for_selected_organizations!([])
      business.add_organization(organization)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_management_changed).never

      assert_logged("Body" => "Enterprise and org have compatible seat management, skipping org seat updates") do
        assert_difference -> { ActionMailer::Base.deliveries.size }, 0 do
          perform_enqueued_jobs(only: ApplicationDeliveryJob) do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::EnterpriseJob.perform_now(
                organization_id: organization.id,
                enterprise_id: business.id,
                action: :add_organization,
                transaction_id: "1234",
                payload: { foo: "bar" },
                actor_id: organization.admins.first.id,
              )
            end
          end
        end
      end

      user_seat = Copilot::SeatAssignment.find_by(assignable_type: "User", assignable_id: user.id)
      refute_nil user_seat
      assert_nil user_seat&.pending_cancellation_date
    end

    test "retains existing organization seat assignments if the enterprise has CfB enabled for all orgs" do
      organization = create(:copilot_for_business_enabled_non_enterprise_organization)
      user = create(:user)
      organization.add_member(user)
      user_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user, assigning_user: organization.admins.first)
      user_seat_assignment.convert_to_seats

      assert_nil user_seat_assignment.pending_cancellation_date

      business = create(:business)
      Copilot::Business.new(business).enable_copilot_for_all_organizations!(business.owners.first)
      business.add_organization(organization)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_management_changed).never

      assert_logged("Body" => "Enterprise and org have compatible seat management, skipping org seat updates") do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseJob.perform_now(
            organization_id: organization.id,
            enterprise_id: business.id,
            action: :add_organization,
            transaction_id: "1234",
            payload: { foo: "bar" },
            actor_id: organization.admins.first.id,
          )
        end
      end

      user_seat = Copilot::SeatAssignment.find_by(assignable_type: "User", assignable_id: user.id)
      refute_nil user_seat
      assert_nil user_seat&.pending_cancellation_date
    end

    test "updates no seat assignments and sends no email when disabling an org that was not already using CfB" do
      organization = create(:organization)
      business = create(:business)
      business.add_organization(organization)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_management_changed).never

      assert_logged("Body" => "Enterprise and org have compatible seat management, skipping org seat updates") do
        assert_difference -> { ActionMailer::Base.deliveries.size }, 0 do
          perform_enqueued_jobs(only: ApplicationDeliveryJob) do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::EnterpriseJob.perform_now(
                organization_id: organization.id,
                enterprise_id: business.id,
                action: :add_organization,
                transaction_id: "1234",
                payload: { foo: "bar" },
                actor_id: organization.admins.first.id,
              )
            end
          end
        end
      end

      organization_seat = Copilot::SeatAssignment.find_by(assignable_type: "Organization", assignable_id: organization.id)
      assert_nil organization_seat
    end

    test "assigns a Copilot plan of business to an the org when copilot is enabled for all organizations" do
      business = create(:business)
      organization = create(:organization)

      Copilot::Business.new(business).enable_copilot_for_all_organizations!
      CopilotForBusinessMailer.expects(:welcome_org_admins).never
      CopilotForBusinessMailer.expects(:welcome_individual).never

      business.add_organization(organization)

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::EnterpriseJob.perform_now(
          organization_id: organization.id,
          enterprise_id: business.id,
          action: :add_organization,
          transaction_id: "1234",
          payload: { foo: "bar" },
          actor_id: organization.admins.first.id,
        )
      end

      assert Copilot::Organization.new(organization).copilot_plan_business?
    end

    test "creates a Copilot Business trial for the organization if it is being added to an eligible business" do
      owner = create(:user)
      organization = create(:organization, admins: [owner])
      business = create(:business, :with_valid_contact_for_billing, owners: [owner], trial_expires_at: Date.current + 30.days)
      business.add_organization(organization)

      business.customer = create :credit_card_customer
      business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)  # Create a payment method
      create(:billing_transaction, transaction_type: "authorization", last_status: "authorized", amount_in_cents: 4, customer: business.customer)  # Create a successful payment
      GitHub.flipper[:digital_front_door_mvp].enable(business)
      assert_predicate business, :eligible_to_trial_copilot_business?

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::EnterpriseJob.perform_now(
          organization_id: organization.id,
          enterprise_id: business.id,
          action: :add_organization,
          transaction_id: "1234",
          payload: { foo: "bar" },
          actor_id: organization.admins.first.id,
        )
      end

      business_trial = Copilot::Organization.new(organization).business_trial
      refute_nil business_trial
      assert_equal business_trial&.state, "pending"
      assert_equal business_trial&.trial_length, business.trial_days_remaining
      assert_equal business_trial&.copilot_plan, "business"
    end

    test "does not create a Copilot Business trial for the organization if it is being added to an eligible business if the digital_front_door_mvp feature flag is disabled" do
      owner = create(:user)
      organization = create(:organization, admins: [owner])
      business = create(:business, owners: [owner], trial_expires_at: Date.current + 30.days)
      create(:account_screening_profile, :no_hit, :with_business, owner: business)
      business.add_organization(organization)

      business.customer = create :credit_card_customer
      business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)  # Create a payment method
      create(:billing_transaction, transaction_type: "authorization", last_status: "authorized", amount_in_cents: 4, customer: business.customer)  # Create a successful payment
      GitHub.flipper[:digital_front_door_mvp].disable
      refute_predicate business, :eligible_to_trial_copilot_business?

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::EnterpriseJob.perform_now(
          organization_id: organization.id,
          enterprise_id: business.id,
          action: :add_organization,
          transaction_id: "1234",
          payload: { foo: "bar" },
          actor_id: organization.admins.first.id,
        )
      end

      business_trial = Copilot::Organization.new(organization).business_trial
      assert_nil business_trial
    end

    test "does not create a Copilot Business trial for the organization if is being added to a business that is not eligible" do
      owner = create(:user)
      organization = create(:organization, admins: [owner])
      business = create(:business, owners: [owner], trial_expires_at: Date.current + 30.days)
      create(:account_screening_profile, :no_hit, :with_business, owner: business)
      business.add_organization(organization)

      business.customer = create :credit_card_customer
      business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)  # Create a payment method
      GitHub.flipper[:digital_front_door_mvp].enable(business)
      refute_predicate business, :eligible_to_trial_copilot_business?  # No successful payment transaction created

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::EnterpriseJob.perform_now(
          organization_id: organization.id,
          enterprise_id: business.id,
          action: :add_organization,
          transaction_id: "1234",
          payload: { foo: "bar" },
          actor_id: organization.admins.first.id,
        )
      end

      business_trial = Copilot::Organization.new(organization).business_trial
      assert_nil business_trial
    end
  end

  context "remove_organization" do
    test "does nothing for org that has no seats or seat assignments and is copilot billable" do
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_management_changed).never
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      organization = create(:organization, :enterprise_linked)

      assert_logged("Body" => "Organization is Copilot billable, keeping seats") do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseJob.perform_now(
            organization_id: organization.id,
            enterprise_id: organization.business.id,
            action: :remove_organization,
            transaction_id: "1234",
            payload: { foo: "bar" },
            actor_id: organization.admins.first.id,
          )
        end
      end

      assert_nil Copilot::SeatAssignment.find_by(owner_id: organization.id)
    end

    test "does nothing for org that has no seats or seat assignments and is not copilot billable" do
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_management_changed).never
      organization = create(:organization, :enterprise_linked)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(false)

      assert Copilot::Organization.new(organization).copilot_disabled?
      assert Copilot::Organization.new(organization).seat_management_disabled?

      assert_logged("Body" => "Organization is not Copilot billable, removing seats if any") do
        refute_logged("Body" => "Removing seat") do
          refute_logged("Body" => "Removing seat assignment") do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::EnterpriseJob.perform_now(
                organization_id: organization.id,
                enterprise_id: organization.business.id,
                action: :remove_organization,
                transaction_id: "1234",
                payload: { foo: "bar" },
                actor_id: organization.admins.first.id,
              )
            end
          end
        end
      end

      assert_nil Copilot::SeatAssignment.find_by(owner_id: organization.id)
    end

    test "does nothing for an organization that is billable with an organization seat assignment" do
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_management_changed).never
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      organization = create(:copilot_for_business_enabled_organization)
      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: organization, assigning_user: organization.admins.first)
      assert_nil seat_assignment.pending_cancellation_date

      copilot_organization = Copilot::Organization.new(organization)
      assert copilot_organization.organization_seat_assignment.present?
      assert_logged("Body" => "Organization is Copilot billable, keeping seats") do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseJob.perform_now(
            organization_id: organization.id,
            enterprise_id: organization.business.id,
            action: :remove_organization,
            transaction_id: "1234",
            payload: { foo: "bar" },
            actor_id: organization.admins.first.id,
          )
        end
      end
    end

    test "cancels stuff for an organization that is NOT billable with an organization seat assignment" do
      organization = create(:organization)
      copilot_org = Copilot::Organization.new(organization)
      refute copilot_org.copilot_billable?

      business = create(:business)
      business.add_organization(organization)

      organization.reload
      assert_equal business, organization.business

      Copilot::Business.new(business).enable_copilot_for_all_organizations!(business.owners.first)
      copilot_org = Copilot::Organization.new(organization)
      copilot_org.seat_management_allow_all!
      assert copilot_org.copilot_for_business_enabled? # this triggers creating the configurations so that's cool

      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: organization, assigning_user: organization.admins.first)
      assert_nil seat_assignment.pending_cancellation_date

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_management_changed).once.with(nil, organization, "enabled_for_all", "disabled")

      assert copilot_org.organization_seat_assignment.present?
      assert_logged("Body" => "Organization is not Copilot billable, removing seats") do
        perform_enqueued_jobs(only: Copilot::SeatManagement::EnterpriseJob) do
          business.remove_organization(organization) # calling this instead of the job directly to get the org actually removed
        end
      end

      refute Copilot::SeatAssignment.exists?(seat_assignment.id)
      assert_equal 0, Copilot::Seat.where(organization: organization).count
      assert Copilot::Organization.new(organization.reload).seat_management_disabled?
      refute Copilot::Organization.new(organization.reload).copilot_for_business_enabled?
    end

    test "has existing teams and users assigned and is billable" do
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)

      copilot_org = Copilot::Organization.new(organization)
      copilot_org.seat_management_selected_teams_and_users!

      user_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user, assigning_user: organization.admins.first)
      user_seat_assignment.convert_to_seats

      assert_nil user_seat_assignment.pending_cancellation_date

      team = create(:team, organization: organization)
      user = create(:user)
      team.add_member(user)
      team_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: team, assigning_user: organization.admins.first)
      team_seat_assignment.convert_to_seats

      assert_nil team_seat_assignment.pending_cancellation_date

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_management_changed).never

      assert_logged("Body" => "Organization is Copilot billable, keeping seats") do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseJob.perform_now(
            organization_id: organization.id,
            enterprise_id: organization.business.id,
            action: :remove_organization,
            transaction_id: "1234",
            payload: { foo: "bar" },
            actor_id: organization.admins.first.id,
          )
        end
      end

      assert Copilot::SeatAssignment.where(id: user_seat_assignment.id).exists?
      assert Copilot::SeatAssignment.where(id: team_seat_assignment.id).exists?
    end

    test "has existing teams and users assigned and is not billable" do
      organization = create(:organization)
      copilot_org = Copilot::Organization.new(organization)
      refute copilot_org.copilot_billable?

      business = create(:business)
      business.add_organization(organization)

      organization.reload
      assert_equal business, organization.business

      Copilot::Business.new(business).enable_copilot_for_all_organizations!(business.owners.first)
      copilot_org = Copilot::Organization.new(organization)
      copilot_org.seat_management_selected_teams_and_users!
      assert copilot_org.copilot_for_business_enabled? # this triggers creating the configurations so that's cool

      user = create(:user)
      organization.add_member(user)
      user_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user, assigning_user: organization.admins.first)
      user_seat_assignment.convert_to_seats

      assert_nil user_seat_assignment.pending_cancellation_date

      team = create(:team, organization: organization)
      user = create(:user)
      team.add_member(user)
      team_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: team, assigning_user: organization.admins.first)
      team_seat_assignment.convert_to_seats

      assert_nil team_seat_assignment.pending_cancellation_date

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_management_changed).once.with(nil, organization, "enabled_for_selected", "disabled")

      assert_logged("Body" => "Removing seat assignment") do
        assert_logged("Body" => "Organization is not Copilot billable, removing seats") do
          perform_enqueued_jobs(only: Copilot::SeatManagement::EnterpriseJob) do
            ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).never

            business.remove_organization(organization)
          end
        end
      end

      refute Copilot::SeatAssignment.where(id: user_seat_assignment.id).exists?
      refute Copilot::SeatAssignment.where(id: team_seat_assignment.id).exists?
      assert Copilot::Organization.new(organization.reload).seat_management_disabled?
      refute Copilot::Organization.new(organization.reload).copilot_for_business_enabled?
    end

    test "destroys an active Copilot Enterprise trial if it exists" do
      organization = create(:copilot_for_business_enabled_organization)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      trial = create(:copilot_business_trial, :organization, copilot_plan: "enterprise", state: "recently_started", trialable: organization)
      user = create(:user)
      organization.add_member(user)

      copilot_org = Copilot::Organization.new(organization)
      copilot_org.seat_management_selected_teams_and_users!

      user_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user, assigning_user: organization.admins.first)
      user_seat_assignment.convert_to_seats

      assert_nil user_seat_assignment.pending_cancellation_date
      assert trial.ongoing?

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_management_changed).never

      assert_logged("Body" => "Organization is Copilot billable, keeping seats") do
        Copilot::SeatManagement::EnterpriseJob.perform_now(
          organization_id: organization.id,
          enterprise_id: organization.business.id,
          action: :remove_organization,
          transaction_id: "1234",
          payload: { foo: "bar" },
          actor_id: organization.admins.first.id,
        )
      end

      assert Copilot::SeatAssignment.where(id: user_seat_assignment.id).exists?
      assert_empty Copilot::BusinessTrial.where(trialable_id: organization.id)
    end

    test "destroys a pending Copilot Enterprise trial if it exists" do
      organization = create(:copilot_for_business_enabled_organization)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      trial = create(:copilot_business_trial, :organization, copilot_plan: "enterprise", state: "pending", trialable: organization)
      user = create(:user)
      organization.add_member(user)

      copilot_org = Copilot::Organization.new(organization)
      copilot_org.seat_management_selected_teams_and_users!

      user_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user, assigning_user: organization.admins.first)
      user_seat_assignment.convert_to_seats

      assert_nil user_seat_assignment.pending_cancellation_date
      assert trial.ongoing?

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_management_changed).never

      assert_logged("Body" => "Organization is Copilot billable, keeping seats") do
        Copilot::SeatManagement::EnterpriseJob.perform_now(
          organization_id: organization.id,
          enterprise_id: organization.business.id,
          action: :remove_organization,
          transaction_id: "1234",
          payload: { foo: "bar" },
          actor_id: organization.admins.first.id,
        )
      end

      assert Copilot::SeatAssignment.where(id: user_seat_assignment.id).exists?
      assert_empty Copilot::BusinessTrial.where(trialable_id: organization.id)
    end

    test "with mixed licenses, automatically downgrades to Copilot Business if the organization is on a non-trial enterprise plan" do
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      GitHub.flipper[:copilot_mixed_licenses].enable

      org = create(:copilot_for_business_enabled_organization)
      biz = org.business
      copilot_biz = Copilot::Business.new(biz)
      copilot_org = Copilot::Organization.new(org)

      copilot_biz.copilot_for_dotcom_enabled!
      copilot_biz.enable_copilot_for_all_organizations!(biz.owners.first)
      copilot_org.seat_management_allow_all!
      copilot_org.copilot_plan_enterprise!

      create(:copilot_seat_assignment, organization: org, assigning_user: org.admins.first, assignable: org).convert_to_seats

      Copilot::Instrumenter.expects(:instrument_copilot_plan_changed).once.with(nil, org, "enterprise", "business")
      CopilotForBusinessMailer.expects(:welcome_org_admins).never
      CopilotForBusinessMailer.expects(:welcome_individual).never

      perform_enqueued_jobs(only: Copilot::SeatManagement::EnterpriseJob) do
        biz.remove_organization(org)
      end

      copilot_org = Copilot::Organization.new(org.reload)

      assert copilot_org.copilot_plan_business?
      assert copilot_org.copilot_for_dotcom_enabled?
      refute copilot_org.copilot_plan_enterprise?
    end
  end

  test "cancels ongoing Copilot Business trial for an organization being removed from a trial business" do
    owner = create(:user)
    organization = create(:organization, admins: [owner])
    business = create(:business, owners: [owner], trial_expires_at: Date.current + 30.days)
    create(:copilot_business_trial, trialable: organization, trialable_type: "Organization", state: :recently_started, ends_at: business.trial_expires_at)
    business.add_organization(organization)
    assert_predicate business.reload, :trial?

    ActiveRecord::Base.connected_to(role: :reading) do
      Copilot::SeatManagement::EnterpriseJob.perform_now(
        organization_id: organization.reload.id,
        enterprise_id: organization.business.id,
        action: :remove_organization,
        transaction_id: "1234",
        payload: { foo: "bar" },
        actor_id: organization.admins.first.id,
      )
    end

    business_trial = Copilot::Organization.new(organization).business_trial
    refute_nil business_trial
    assert_equal business_trial&.state, "canceled"
    assert_equal business_trial&.copilot_plan, "business"
  end

  test "does not cancel ongoing Copilot Business trial for an organization being removed from a non-trial business" do
    owner = create(:user)
    organization = create(:organization, admins: [owner])
    business = create(:business, owners: [owner])
    create(:copilot_business_trial, trialable: organization, trialable_type: "Organization", state: :recently_started, ends_at: Date.current + 30.days)
    business.add_organization(organization)
    refute_predicate business.reload, :trial?

    ActiveRecord::Base.connected_to(role: :reading) do
      Copilot::SeatManagement::EnterpriseJob.perform_now(
        organization_id: organization.reload.id,
        enterprise_id: organization.business.id,
        action: :remove_organization,
        transaction_id: "1234",
        payload: { foo: "bar" },
        actor_id: organization.admins.first.id,
      )
    end

    business_trial = Copilot::Organization.new(organization).business_trial
    refute_nil business_trial
    assert_equal business_trial&.state, "recently_started"
    assert_equal business_trial&.copilot_plan, "business"
  end
end if GitHub.copilot_enabled?
