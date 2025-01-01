# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Conditions
    # Helper to create a targetable object for a Enterprise
    # Long-term, it may make sense to have Enterprise implement Targetable directly if we choose to use
    # Targetable as a universal interface for all targetable objects
    class Targets::Enterprise

      include Targetable

      sig { params(business: Business).void }
      def initialize(business:)
        @business = business
      end

      sig { override.returns(T::Hash[RuleEngine::Conditions::Targetable::Attribute, T.untyped]) }
      def targetable_attributes
        {
          Attribute::Enterprise => @business,
        }
      end

      sig { override.returns(Promise[T.nilable(RuleEngine::Conditions::Targetable)]) }
      def async_targetable_parent
        T.cast(Promise.resolve(nil), Promise[T.nilable(RuleEngine::Conditions::Targetable)])
      end
    end
  end
end
