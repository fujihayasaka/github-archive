# typed: strict
# frozen_string_literal: true

module Copilot
  class PlanComponent < ApplicationComponent
    extend T::Sig

    sig { returns(Copilot::Business) }
    attr_reader :copilot_business

    sig { params(copilot_business: Copilot::Business).void }
    def initialize(copilot_business)
      @copilot_business = T.let(copilot_business, Copilot::Business)
    end

    sig { returns(String) }
    memoize def current_plan
      "Copilot #{copilot_business.copilot_plan.capitalize}"
    end

    sig { returns(T.nilable(::Organization)) }
    memoize def named_organization
      first_seat = Copilot::Seat.for_business(copilot_business.business_object).first
      return first_seat.organization if first_seat

      organizations.first
    end

    sig { returns(ActiveRecord::Relation) }
    memoize def organizations
      copilot_business.business_object.organizations
    end
  end
end
