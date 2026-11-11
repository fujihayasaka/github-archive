# typed: strict
# frozen_string_literal: true

module Targeting
  # Helper to create a targetable object for an Enterprise
  # Long-term, it may make sense to have Enterprise implement Targetable directly if we choose to use
  # Targetable as a universal interface for all targetable objects
  class Targets::Enterprise

    include Targetable

    sig { params(business: Business).void }
    def initialize(business:)
      @business = business
    end

    sig { override.returns(Business) }
    def internal_record
      @business
    end

    sig { override.returns(T::Hash[Targeting::Attribute, T.untyped]) }
    def targetable_attributes
      {
        Attribute::Enterprise => @business,
      }
    end

    sig { override.returns(Promise[T::Array[Targeting::Targetable]]) }
    def async_targetable_parents
      Promise.resolve(T.let([], T::Array[Targeting::Targetable]))
    end
  end
end
