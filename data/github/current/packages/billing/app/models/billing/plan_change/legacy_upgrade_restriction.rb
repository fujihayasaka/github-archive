# typed: true
# frozen_string_literal: true

module Billing
  class PlanChange::LegacyUpgradeRestriction
    attr_reader :target, :actor

    def initialize(target:, actor:)
      @target = target
      @actor = actor
    end

    def is_gold_or_lower?(plan)
      return true if plan.free?
      return true if plan.repos <= GitHub::Plan.gold.repos
    end

    def allow_plan?(plan)
      return true if is_gold_or_lower?(plan)
      return false if plan.repos > target.plan.repos
      true
    end
  end
end
