# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingPlanChangeLegacyUpgradeRestrictionTest < GitHub::TestCase
  context "#allow_plan?" do
    test "should allow per-repo plans below current plan" do
      org = build(:organization, plan: :aluminium)
      user = build(:user)
      restriction = Billing::PlanChange::LegacyUpgradeRestriction.new(target: org, actor: user)

      [GitHub::Plan.bronze, GitHub::Plan.gold, GitHub::Plan.platinum].each do |plan|
        assert restriction.allow_plan?(plan), "#{plan} should be allowed"
      end
    end

    test "should forbid per-repo plans above current plan" do
      org = build(:organization, plan: :mendelevium)
      user = build(:user)
      restriction = Billing::PlanChange::LegacyUpgradeRestriction.new(target: org, actor: user)

      [GitHub::Plan.curium, GitHub::Plan.aluminium].each do |plan|
        refute restriction.allow_plan?(plan), "#{plan} should be forbidden"
      end
    end

    test "should allow gold plan for orgs on silver and below" do
      org = build(:organization, plan: :bronze)
      user = build(:user)
      restriction = Billing::PlanChange::LegacyUpgradeRestriction.new(target: org, actor: user)

      [GitHub::Plan.bronze, GitHub::Plan.silver, GitHub::Plan.gold].each do |plan|
        assert restriction.allow_plan?(plan), "#{plan} should be allowed"
      end
    end
  end

  context "#is_gold_or_lower" do
    test "it returns true if the plan is free" do
      org = build(:organization, plan: "free")
      user = build(:user)

      restriction = Billing::PlanChange::LegacyUpgradeRestriction.new(target: org, actor: user)

      assert restriction.is_gold_or_lower?(org.plan)
    end

    test "it returns true if the plan is silver" do
      org = build(:organization, plan: "silver")
      user = build(:user)

      restriction = Billing::PlanChange::LegacyUpgradeRestriction.new(target: org, actor: user)

      assert restriction.is_gold_or_lower?(org.plan)
    end

    test "it returns false if the plan is platinum" do
      org = build(:organization, plan: "platinum")
      user = build(:user)

      restriction = Billing::PlanChange::LegacyUpgradeRestriction.new(target: org, actor: user)

      refute restriction.is_gold_or_lower?(org.plan)
    end

    test "it returns true if the plan is gold" do
      org = build(:organization, plan: "gold")
      user = build(:user)

      restriction = Billing::PlanChange::LegacyUpgradeRestriction.new(target: org, actor: user)

      assert restriction.is_gold_or_lower?(org.plan)
    end
  end
end
