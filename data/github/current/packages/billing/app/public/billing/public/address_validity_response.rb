# typed: strict
# frozen_string_literal: true

module  Billing
  module Public
    class AddressValidityResponse < T::Struct

      const :valid, T::Boolean, default: false
      const :error, String, default: ""
      const :suggested_postal_code, T.nilable(String), default: nil

      sig { returns(T::Boolean) }
      attr_accessor :valid

      sig { returns(String) }
      attr_accessor :error

      sig { returns(T.nilable(String)) }
      attr_accessor :suggested_postal_code
    end
  end
end
