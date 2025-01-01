# typed: strict
# frozen_string_literal: true

module Billing
  class PlanTransition
    extend T::Sig

    sig { returns(GitHub::Plan) }
    attr_reader :old_plan

    sig { returns(GitHub::Plan) }
    attr_reader :new_plan

    sig do
      params(
        target: ::User,
        new_plan_name: T.nilable(T.any(String, Symbol, GitHub::Plan))
      ).void
    end
    def initialize(target, new_plan_name)
      @target = target
      @old_plan = T.let(target.plan, GitHub::Plan)
      @new_plan = T.let(GitHub::Plan.find(new_plan_name) || @old_plan, GitHub::Plan)
    end

    sig { returns(String) }
    def target_type
      @target.type
    end

    sig { returns(T::Boolean) }
    def organization?
      @target.organization?
    end

    sig { returns(T::Boolean) }
    def billing?
      @target.has_valid_payment_method?
    end

    sig { returns(T::Boolean) }
    def plan_changed?
      new_plan != old_plan
    end

    sig { returns(T::Boolean) }
    def cost_changed?
      new_plan.cost != old_plan.cost
    end

    sig { returns(T.nilable(String)) }
    def cost_change_label
      if new_plan.cost > old_plan.cost
        "upgrade"
      elsif new_plan.cost < old_plan.cost
        "downgrade"
      end
    end
  end
end
