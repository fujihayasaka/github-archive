# typed: strict
# frozen_string_literal: true

module Targeting
  # Helper to create a targetable object for a User
  # Long-term, it may make sense to have User implement Targetable directly if we choose to use
  # Targetable as a universal interface for all targetable objects
  class Targets::User
    include Targetable

    sig { params(user: Users::IUser).void }
    def initialize(user:)
      @user = user
    end

    sig { override.returns(Users::IUser) }
    def internal_record
      @user
    end

    sig { override.returns(T::Hash[Targeting::Attribute, T.untyped]) }
    def targetable_attributes
      {
        Attribute::User => @user,
      }
    end

    sig { override.returns(Promise[T::Array[Targeting::Targetable]]) }
    def async_targetable_parents
      Promise.resolve(T.let([], T::Array[Targeting::Targetable]))
    end
  end
end
