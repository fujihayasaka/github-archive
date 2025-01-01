# typed: strict
# frozen_string_literal: true

module Copilot
  class SeatCostComponent < ApplicationComponent

    BUSINESS_PLAN_SEAT_COST = 19
    ENTERPRISE_PLAN_SEAT_COST = 39

    sig { returns(Copilot::Business) }
    attr_reader :copilot_business

    sig { returns(::Business) }
    attr_reader :business

    sig { params(copilot_business: Copilot::Business).void }
    def initialize(copilot_business)
      @copilot_business = T.let(copilot_business, Copilot::Business)
      @business = T.let(copilot_business.business_object, ::Business)
    end

    sig { returns(Integer) }
    def plan_cost
      copilot_business.copilot_plan_business? ? BUSINESS_PLAN_SEAT_COST : ENTERPRISE_PLAN_SEAT_COST
    end

    sig { returns(Integer) }
    memoize def estimated_cost
      copilot_trials = copilot_business.ongoing_organization_trials

      # If there are trials and they are not all for the same plan, we need to calculate the cost differently
      if copilot_trials.any?
        orgs = copilot_trials.map(&:trialable)
        enterprise_trial_orgs = copilot_trials.select(&:copilot_plan_enterprise?).map(&:trialable)
        non_trial_orgs = business.organizations - orgs

        # Enterprise trials require a business plan, so they are charged at the business rate
        return (Copilot::Seat.where(organization: enterprise_trial_orgs).count * BUSINESS_PLAN_SEAT_COST) +
          (Copilot::Seat.where(organization: non_trial_orgs).count * plan_cost)
      end

      copilot_business.copilot_enabled_members_count * plan_cost
    end

    sig { returns(String) }
    def billing_overview_path
      enterprise_billing_path(business)
    end

    sig { returns(T::Hash[Symbol, Integer]) }
    memoize def seat_counts_by_license
      copilot_business.copilot_enabled_members_count_by_license
    end

    sig { returns(Integer) }
    def copilot_business_seats_count
      seat_counts_by_license[:business].to_i
    end

    sig { returns(Integer) }
    def copilot_enterprise_seats_count
      seat_counts_by_license[:enterprise].to_i
    end
  end
end
