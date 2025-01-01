
# typed: strict
# frozen_string_literal: true

module AccountSwitcher
  class StashedAccounts < T::Struct
    extend T::Sig

    prop :valid, T::Array[StashedAccount]
    prop :invalid, T::Array[StashedAccount]

    sig { returns(T::Boolean) }
    def any?
      valid.any? || invalid.any?
    end

    sig { returns(T::Array[StashedAccount]) }
    def all
      valid + invalid
    end
  end
end
