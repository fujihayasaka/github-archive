# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingPlanTrialTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @plan = "business_plus"
    @plan_trial = create(:billing_plan_trial, :active, user: @user, plan: @plan)
  end

  context "#active?" do
    test "returns true when the associated pending plan change is not complete" do
      assert @plan_trial.active?
    end

    test "returns false when the associated pending plan change is complete" do
      @plan_trial.pending_plan_change.update(is_complete: true)

      refute @plan_trial.active?
    end

    test "returns false when the associated pending plan change has been deleted" do
      @plan_trial.pending_plan_change.destroy
      @plan_trial.reload

      refute @plan_trial.active?
    end
  end

  context "#expires_within?" do
    test "returns false when trial is active" do
      @plan_trial.pending_plan_change.update(is_complete: false, active_on: 15.days.ago)

      refute @plan_trial.reload.expired_within?(20.days)
    end

    test "returns true when trial is inactive and expired within the number of days given" do
      @plan_trial.pending_plan_change.update(is_complete: true, active_on: 15.days.ago)

      assert @plan_trial.reload.expired_within?(20.days)
    end

    test "returns false when trial is inactive expired outside the number of days given" do
      @plan_trial.pending_plan_change.update(is_complete: true, active_on: 15.days.ago)

      refute @plan_trial.expired_within?(10.days)
    end

    test "returns false when trial's pending plan change has been deleted" do
      @plan_trial.pending_plan_change.destroy
      @plan_trial.reload

      refute @plan_trial.expired_within?(10.days)
    end
  end

  context "for_plan scope" do
    test "filters to plan trials for the given plan" do
      plan_name = "business_plus"
      trial1 = create(:billing_plan_trial, plan: plan_name)
      trial2 = create(:billing_plan_trial, plan: "pro")
      trial3 = create(:billing_plan_trial, plan: plan_name)

      result = Billing::PlanTrial.for_plan(plan_name).where(id: [trial1.id, trial2.id, trial3.id])

      assert_same_elements [trial1, trial3], result
    end
  end

  context "for_user scope" do
    test "filters to plan trials for the given user" do
      user = create(:user)
      trial1 = create(:billing_plan_trial, :expired, user: user, plan: "pro")
      trial2 = create(:billing_plan_trial)
      trial3 = create(:billing_plan_trial, user: user)

      result = Billing::PlanTrial.for_user(user).where(id: [trial1.id, trial2.id, trial3.id])

      assert_same_elements [trial1, trial3], result
    end
  end
end
