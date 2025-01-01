# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingEnterpriseCloudTrialTest < GitHub::TestCase
  include HydroTestHelpers
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @org = create(:free_organization, seats: 0)
  end

  context "#description" do
    test "returns a description of an expired trial" do
      trial = Billing::EnterpriseCloudTrial.new(@org)
      assert_predicate trial, :expired?

      assert_equal "The trial expired 0 days ago.", trial.description
    end

    test "returns a description of a non-expired trial" do
      travel_to "2023-11-13"
      pending_plan_change = create(:billing_pending_plan_change, is_complete: false)
      travel_to(3.days.ago) do
        create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")
      end
      trial = Billing::EnterpriseCloudTrial.new(@org)

      assert_equal "The trial has been active for 3 days and has 0 days remaining.", trial.description
    end
  end

  context "hydro", skip_enterprise: true do
    test "creates trial signup event on create" do
      reset_hydro
      Billing::EnterpriseCloudTrial.new(@org).create

      assert_hydro_published({
        account: Hydro::EntitySerializer.user(@org),
        previous_plan: "free",
        current_plan: "business_plus",
      }, schema: "github.billing.v0.TrialSignup")
    end

    test "creates trial extended event on trial extension" do
      trial = Billing::EnterpriseCloudTrial.new(@org)
      trial.create
      reset_hydro

      trial.extend_trial(5.days)

      assert_hydro_published({
        account: Hydro::EntitySerializer.user(@org),
        previous_duration_in_days: 30,
        new_duration_in_days: 35,
      }, schema: "github.billing.v0.TrialExtended")
    end
  end

  context "#create" do
    test "creates an enterprise cloud trial for 50 seats and associated pending plan change" do
      freeze_time do
        assert Billing::EnterpriseCloudTrial.new(@org).create

        @org.reload

        pending_plan_change = @org.pending_plan_changes.find_by(plan: "free", seats: 0, active_on: (GitHub::Billing.now + 30.days).to_date)

        assert_equal "business_plus", @org.read_attribute(:plan)
        assert_equal 50, @org.seats
        assert_equal 1, @org.pending_plan_changes.count
        assert pending_plan_change
        assert Billing::PlanTrial.exists?(user: @org, plan: "business_plus", pending_plan_change: pending_plan_change)
      end
    end

    test "creates an enterprise cloud trial with same seats and associated pending plan change for teams" do
      freeze_time do
        seat_count = 40
        @org = create(:business_organization, seats: seat_count)
        assert Billing::EnterpriseCloudTrial.new(@org).create

        pending_plan_change = @org.pending_plan_changes.find_by(plan: "business", seats: seat_count, active_on: (GitHub::Billing.now + 30.days).to_date)

        assert_equal "business_plus", @org.read_attribute(:plan)
        assert_equal seat_count, @org.seats
        assert_equal 1, @org.pending_plan_changes.count
        assert pending_plan_change
        assert Billing::PlanTrial.exists?(user: @org, plan: "business_plus", pending_plan_change: pending_plan_change)
      end
    end

    test "enqueues the enterprise cloud trial check job to display the trial banner" do
      assert_enqueued_with(job: Billing::EnterpriseCloudTrialCheckJob, args: [@org.id], queue: "billing") do
        Billing::EnterpriseCloudTrial.new(@org).create
      end
    end if GitHub.billing_enabled?

    test "returns false if organization is ineligible" do
      @org = create(:free_organization)
      _past_trial = create(:billing_plan_trial, user: @org)

      assert_difference -> { Billing::PlanTrial.count } => 0 do
        refute Billing::EnterpriseCloudTrial.new(@org).create
      end
    end

    test "creates a trial signup audit log event" do
      trial =  Billing::EnterpriseCloudTrial.new(@org)

      events = assert_performed_audit_entries(count: 1, only: "billing.trial_start") do
        trial.create
      end

      expected_payload = {
        action: "billing.trial_start",
        org: @org.login,
        org_id: @org.id,
      }

      assert_subset_hash expected_payload, events.first
    end
  end

  context "#plan_trial" do
    test "can be batch loaded for multiple Enterprise Cloud trials efficiently" do
      org1, org2 = create_pair(:business_organization)
      enterprise_cloud_trial_wo_plan_trial1 = Billing::EnterpriseCloudTrial.new(org1)
      enterprise_cloud_trial_wo_plan_trial2 = Billing::EnterpriseCloudTrial.new(org2)

      free_org1, free_org2, free_org3, free_org4 = create_list(:free_organization, 4, seats: 0)
      plan_trial1 = create(:billing_plan_trial, :active, user: free_org1, plan: GitHub::Plan::BUSINESS_PLUS)
      plan_trial2 = create(:billing_plan_trial, :active, user: free_org2, plan: GitHub::Plan::BUSINESS_PLUS)
      enterprise_cloud_trial_w_plan_trial1 = Billing::EnterpriseCloudTrial.new(free_org1)
      enterprise_cloud_trial_w_plan_trial2 = Billing::EnterpriseCloudTrial.new(free_org2)

      expired_plan_trial1 = create(:billing_plan_trial, :expired, user: free_org3, plan: GitHub::Plan::BUSINESS_PLUS)
      expired_plan_trial2 = create(:billing_plan_trial, :expired, user: free_org4, plan: GitHub::Plan::BUSINESS_PLUS)
      enterprise_cloud_trial_w_expired_plan_trial1 = Billing::EnterpriseCloudTrial.new(free_org3)
      enterprise_cloud_trial_w_expired_plan_trial2 = Billing::EnterpriseCloudTrial.new(free_org4)

      trials = [enterprise_cloud_trial_wo_plan_trial1, enterprise_cloud_trial_wo_plan_trial2,
        enterprise_cloud_trial_w_plan_trial1, enterprise_cloud_trial_w_plan_trial2,
        enterprise_cloud_trial_w_expired_plan_trial1, enterprise_cloud_trial_w_expired_plan_trial2]

      assert_query_count(1) do
        GitHub::PrefillAssociations.prefill_batch_method(trials, :plan_trial)
      end

      assert_query_count(0) do
        assert_nil enterprise_cloud_trial_wo_plan_trial1.plan_trial
        assert_nil enterprise_cloud_trial_wo_plan_trial2.plan_trial
        assert_equal plan_trial1, enterprise_cloud_trial_w_plan_trial1.plan_trial
        assert_equal plan_trial2, enterprise_cloud_trial_w_plan_trial2.plan_trial
        assert_equal expired_plan_trial1, enterprise_cloud_trial_w_expired_plan_trial1.plan_trial
        assert_equal expired_plan_trial2, enterprise_cloud_trial_w_expired_plan_trial2.plan_trial
      end
    end
  end

  context "#deactivate!" do
    test "creates a trial ended audit log event" do
      trial = Billing::EnterpriseCloudTrial.new(@org)
      trial.create

      events = assert_performed_audit_entries(count: 1, only: "billing.trial_end") do
        trial.deactivate!
      end

      expected_payload = {
        action: "billing.trial_end",
        org: @org.login,
        org_id: @org.id,
      }

      assert_subset_hash expected_payload, events.first
    end

    test "updates terms to CTOS" do
      org = create(:organization)
      org.terms_of_service.update(type: "Evaluation", actor: org.admins.first)
      Billing::EnterpriseCloudTrial.new(org).create
      Billing::EnterpriseCloudTrial.new(org).deactivate!

      assert org.reload.terms_of_service.corporate?
    end

    test "does not update terms when terms are not evaluation" do
      org = create(:organization)
      org.terms_of_service.update(type: "Standard", actor: org.admins.first)
      trial = Billing::EnterpriseCloudTrial.new(org)
      trial.create

      trial.deactivate!

      assert org.reload.terms_of_service.standard?
    end

    test "sets pending plan change as complete" do
      org = create(:organization)
      trial = Billing::EnterpriseCloudTrial.new(org)
      trial.create

      trial.deactivate!

      refute trial.active?
    end
  end

  context "#eligible?" do
    test "returns true for organizations with no past enterprise trials" do
      assert Billing::EnterpriseCloudTrial.new(@org).eligible?
    end

    test "returns true when organization is nil" do
      assert Billing::EnterpriseCloudTrial.new(nil).eligible?
    end

    test "returns false for organizations with past enterprise trials" do
      _past_trial = create(:billing_plan_trial, user: @org)

      refute Billing::EnterpriseCloudTrial.new(@org).eligible?
    end
  end

  context ".eligible_orgs_only" do
    test "returns organizations with no past enterprise trials" do
      another_org = create(:organization)
      assert_equal [@org, another_org], Billing::EnterpriseCloudTrial.eligible_orgs_only([@org, another_org])
    end

    test "filters out organizations with past enterprise trials" do
      another_org = create(:organization)
      create(:billing_plan_trial, user: @org)
      assert_equal [another_org], Billing::EnterpriseCloudTrial.eligible_orgs_only([@org, another_org])
    end

    test "returns empty list when there are no eligible organization" do
      another_org = create(:organization)
      create(:billing_plan_trial, user: @org)
      create(:billing_plan_trial, user: another_org)
      assert_empty Billing::EnterpriseCloudTrial.eligible_orgs_only([@org, another_org])
    end

    test "returns empty list when no organization was given" do
      assert_empty Billing::EnterpriseCloudTrial.eligible_orgs_only([])
    end
  end

  context "#active?" do
    test "returns false if organization does not have a trial" do
      refute Billing::EnterpriseCloudTrial.new(@org).active?
    end

    test "returns true if pending plan change is incomplete" do
      pending_plan_change = create(:billing_pending_plan_change, is_complete: false)
      create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

      assert Billing::EnterpriseCloudTrial.new(@org).active?
    end

    test "returns false if pending plan change is complete" do
      pending_plan_change = create(:billing_pending_plan_change, is_complete: true)
      create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

      refute Billing::EnterpriseCloudTrial.new(@org).active?
    end

    test "can be batch loaded for multiple Enterprise Cloud trials efficiently" do
      org1, org2 = create_pair(:business_organization)
      enterprise_cloud_trial_wo_plan_trial1 = Billing::EnterpriseCloudTrial.new(org1)
      enterprise_cloud_trial_wo_plan_trial2 = Billing::EnterpriseCloudTrial.new(org2)

      free_org1, free_org2, free_org3, free_org4 = create_list(:free_organization, 4, seats: 0)
      create(:billing_plan_trial, :active, user: free_org1, plan: GitHub::Plan::BUSINESS_PLUS)
      create(:billing_plan_trial, :active, user: free_org2, plan: GitHub::Plan::BUSINESS_PLUS)
      enterprise_cloud_trial_w_plan_trial1 = Billing::EnterpriseCloudTrial.new(free_org1)
      enterprise_cloud_trial_w_plan_trial2 = Billing::EnterpriseCloudTrial.new(free_org2)

      create(:billing_plan_trial, :expired, user: free_org3, plan: GitHub::Plan::BUSINESS_PLUS)
      create(:billing_plan_trial, :expired, user: free_org4, plan: GitHub::Plan::BUSINESS_PLUS)
      enterprise_cloud_trial_w_expired_plan_trial1 = Billing::EnterpriseCloudTrial.new(free_org3)
      enterprise_cloud_trial_w_expired_plan_trial2 = Billing::EnterpriseCloudTrial.new(free_org4)

      trials = [enterprise_cloud_trial_wo_plan_trial1, enterprise_cloud_trial_wo_plan_trial2,
        enterprise_cloud_trial_w_plan_trial1, enterprise_cloud_trial_w_plan_trial2,
        enterprise_cloud_trial_w_expired_plan_trial1, enterprise_cloud_trial_w_expired_plan_trial2]

      assert_query_count(2) do
        GitHub::PrefillAssociations.prefill_batch_method(trials, :active?)
      end

      assert_query_count(0) do
        refute_predicate enterprise_cloud_trial_wo_plan_trial1, :active?
        refute_predicate enterprise_cloud_trial_wo_plan_trial2, :active?
        assert_predicate enterprise_cloud_trial_w_plan_trial1, :active?
        assert_predicate enterprise_cloud_trial_w_plan_trial2, :active?
        refute_predicate enterprise_cloud_trial_w_expired_plan_trial1, :active?
        refute_predicate enterprise_cloud_trial_w_expired_plan_trial2, :active?
      end
    end
  end

  context ".trial_exists_for?" do
    test "returns true if there is a trial after the date" do
      freeze_time do
        create(:billing_plan_trial, user: @org, plan: "business_plus", created_at: 3.days.ago)

        assert Billing::EnterpriseCloudTrial.trial_exists_for?(@org.id, created_after: 4.days.ago)
      end
    end

    test "returns false if there is no trial after the date" do
      freeze_time do
        create(:billing_plan_trial, user: @org, plan: "business_plus", created_at: 5.days.ago)

        refute Billing::EnterpriseCloudTrial.trial_exists_for?(@org.id, created_after: 4.days.ago)
      end
    end
  end

  context "#days_active" do
    test "returns number of days trial has been active" do
      travel_to Time.zone.local(1979, 6, 15, 10, 32, 0) do
        pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 13.days)
        create(
          :billing_plan_trial,
          user: @org,
          pending_plan_change: pending_plan_change,
          plan: "business_plus",
          created_at: 3.days.ago,
        )

        assert_equal 3, Billing::EnterpriseCloudTrial.new(@org).days_active
      end
    end
  end

  context "#days_remaining" do
    test "returns 0 if trial is no longer active" do
      freeze_time do
        pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 13.days, is_complete: true)
        create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

        assert_equal 0, Billing::EnterpriseCloudTrial.new(@org).days_remaining
      end
    end

    test "returns days remaining in trial" do
      freeze_time do
        pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 13.days)
        create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

        assert_equal 13, Billing::EnterpriseCloudTrial.new(@org).days_remaining
      end
    end

    test "returns 0 if the pending plan change has been deleted" do
      freeze_time do
        pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 13.days)
        create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")
        pending_plan_change.destroy

        assert_equal 0, Billing::EnterpriseCloudTrial.new(@org).days_remaining
      end
    end
  end

  context "#time_remaining" do
    test "returns time remaining in trial" do
      travel_to Time.zone.local(1979, 6, 15, 10, 32, 0) do
        pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 13.days)
        create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")


        assert_equal "13", T.cast(Billing::EnterpriseCloudTrial.new(@org).time_remaining, Time).strftime("%d")
      end
    end

    test "returns zero if the pending plan change has been deleted" do
      travel_to Time.zone.local(1979, 6, 15, 10, 32, 0) do
        pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 13.days)
        create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")
        pending_plan_change.destroy

        assert_equal 0, Billing::EnterpriseCloudTrial.new(@org).time_remaining
      end
    end
  end

  context "#duration_in_days" do
    test "returns time remaining in trial" do
      travel_to Time.zone.local(1979, 6, 15, 10, 32, 0) do
        pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 13.days)
        create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

        assert_equal 13, Billing::EnterpriseCloudTrial.new(@org).duration_in_days
      end
    end

    test "returns zero if the pending plan change has been deleted" do
      travel_to Time.zone.local(1979, 6, 15, 10, 32, 0) do
        pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 13.days)
        create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")
        pending_plan_change.destroy

        assert_equal 0, Billing::EnterpriseCloudTrial.new(@org).duration_in_days
      end
    end
  end

  context "#extend_trial" do
    test "un-completes pending plan change and extends active_on date by given days" do
      freeze_time do
        pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today, is_complete: true)
        create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

        trial = Billing::EnterpriseCloudTrial.new(@org)

        assert trial.extend_trial(14.days)

        pending_plan_change.reload
        assert_equal 14, trial.days_remaining
        assert_equal GitHub::Billing.today + 14.days, pending_plan_change.active_on
        refute pending_plan_change.is_complete
      end
    end

    test "does not allow extensions over 90 days" do
      freeze_time do
        pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 14.days, is_complete: true)
        create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

        trial = Billing::EnterpriseCloudTrial.new(@org)

        refute trial.extend_trial(77.days)
      end
    end

    test "can extend trial over max allowed days if ignore_max is true" do
      freeze_time do
        pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 14.days, is_complete: true)
        create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

        trial = Billing::EnterpriseCloudTrial.new(@org)

        assert trial.extend_trial(1000.days, ignore_max: true)
      end
    end

    test "creates a trial extended audit log event" do
      freeze_time do
        pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today, is_complete: false)
        create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

        trial = Billing::EnterpriseCloudTrial.new(@org)

        events = assert_performed_audit_entries(count: 1, only: "billing.trial_extend") do
          assert trial.extend_trial(14.days)
        end

        expected_payload = {
          action: "billing.trial_extend",
          duration_in_days_was: 0,
          duration_in_days: 14,
          org: @org.login,
          org_id: @org.id,
        }

        assert_subset_hash expected_payload, events.first
      end
    end

    test "does not allow extensions when the pending plan change is deleted" do
      freeze_time do
        pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today, is_complete: true)
        create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")
        pending_plan_change.destroy

        trial = Billing::EnterpriseCloudTrial.new(@org)

        refute trial.extend_trial(14.days)
      end
    end
  end

  context "can_extend_trial?" do
    test "returns true when not over MAX_TRIAL_LENGTH" do
      pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 14.days, is_complete: true)
      create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

      trial = Billing::EnterpriseCloudTrial.new(@org)

      assert trial.can_extend_trial?(14.days)
    end

    test "returns false when over MAX_TRIAL_LENGTH" do
      pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 14.days, is_complete: true)
      create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

      trial = Billing::EnterpriseCloudTrial.new(@org)

      refute trial.can_extend_trial?(77.days)
    end

    test "returns false if the pending plan change has been deleted" do
      pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 14.days, is_complete: true)
      create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")
      pending_plan_change.destroy

      trial = Billing::EnterpriseCloudTrial.new(@org)

      refute trial.can_extend_trial?(14.days)
    end
  end

  context "#expires_on" do
    test "returns pending_plan_change active_on" do
      pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today, is_complete: true)
      create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

      trial = Billing::EnterpriseCloudTrial.new(@org)

      assert_equal pending_plan_change.active_on, trial.expires_on
    end

    test "returns nil if the pending plan change has been deleted" do
      pending_plan_change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today, is_complete: true)
      create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")
      pending_plan_change.destroy

      trial = Billing::EnterpriseCloudTrial.new(@org)

      assert_nil trial.expires_on
    end
  end

  context "#expired?" do
    test "returns true if organization does not have a trial" do
      assert Billing::EnterpriseCloudTrial.new(@org).expired?
    end

    test "returns false if pending plan change is incomplete" do
      pending_plan_change = create(:billing_pending_plan_change, is_complete: false)
      create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

      refute Billing::EnterpriseCloudTrial.new(@org).expired?
    end

    test "returns true if pending plan change is complete" do
      pending_plan_change = create(:billing_pending_plan_change, is_complete: true)
      create(:billing_plan_trial, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

      assert Billing::EnterpriseCloudTrial.new(@org).expired?
    end
  end

  context "#ever_been_in_trial?" do
    test "returns true when a plan_trial exists" do
      create(:billing_plan_trial, user: @org, plan: "business_plus")

      trial = Billing::EnterpriseCloudTrial.new(@org)

      assert trial.ever_been_in_trial?
    end

    test "returns false when a plan_trial does not" do
      trial = Billing::EnterpriseCloudTrial.new(@org)

      refute trial.ever_been_in_trial?
    end
  end

  context "#difference_between_plan_trial_creation" do
    test "returns the difference between the creation of plan trial" do
      freeze_time do
        trial = Billing::EnterpriseCloudTrial.new(@org)
        trial.create
        plan_change = T.must(Billing::PlanTrial.find_by!(user: @org).pending_plan_change)

        assert_equal 2.hours, trial.difference_between_plan_trial_creation(T.must(plan_change.created_at) - 2.hours)
      end
    end
  end

  context "#should_display_banner_for?" do
    test "returns false if org has already converted" do
      pending_plan_change = create(:billing_pending_plan_change, is_complete: true)
      create(:billing_plan_trial, :expired, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

      user = create(:user)
      @org.add_member(user)
      @org.plan = GitHub::Plan.business_plus

      refute Billing::EnterpriseCloudTrial.new(@org).should_display_banner_for?(user)
    end

    test "returns false if org has not been in trial" do
      create(:billing_pending_plan_change, is_complete: true)

      user = create(:user)
      @org.add_member(user)

      refute Billing::EnterpriseCloudTrial.new(@org).should_display_banner_for?(user)
    end

    test "returns false if user is not part of org" do
      pending_plan_change = create(:billing_pending_plan_change, is_complete: true)
      create(:billing_plan_trial, :expired, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

      user = create(:user)

      refute Billing::EnterpriseCloudTrial.new(@org).should_display_banner_for?(user)
    end

    test "returns false if it has been over 7 days since trial expiry" do
      pending_plan_change = create(:billing_pending_plan_change, is_complete: true, active_on: GitHub::Billing.today - 8.days)
      create(:billing_plan_trial, :expired, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")

      user = create(:user)
      @org.add_member(user)

      refute Billing::EnterpriseCloudTrial.new(@org).should_display_banner_for?(user)
    end

    test "returns false if the trial ends early" do
      today = GitHub::Billing.today
      travel_to(2.weeks.ago) do
        pending_plan_change = create(:billing_pending_plan_change, is_complete: true, active_on: today)
        create(:billing_plan_trial, :expired, user: @org, pending_plan_change: pending_plan_change, plan: "business_plus")
      end

      user = create(:user)
      @org.add_member(user)

      refute Billing::EnterpriseCloudTrial.new(@org).should_display_banner_for?(user)
    end
  end
end
