# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Conditions
    # Helper to create a targetable object for a User
    # Long-term, it may make sense to have User implement Targetable directly if we choose to use
    # Targetable as a universal interface for all targetable objects
    class Targets::User

      include Targetable

      sig { params(user: User).void }
      def initialize(user:)
        @user = user
      end

      sig { override.returns(T::Hash[RuleEngine::Conditions::Targetable::Attribute, T.untyped]) }
      def targetable_attributes
        {
          Attribute::User => @user,
        }
      end

      sig { override.returns(Promise[T.nilable(RuleEngine::Conditions::Targetable)]) }
      def async_targetable_parent
        T.cast(Promise.resolve(nil), Promise[T.nilable(RuleEngine::Conditions::Targetable)])
      end
    end
  end
end
