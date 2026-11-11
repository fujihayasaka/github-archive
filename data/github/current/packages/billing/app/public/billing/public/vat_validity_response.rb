# typed: strict
# frozen_string_literal: true

module Billing
  module Public
    class VatValidityResponse < T::Struct
      const :valid, T::Boolean, default: false
      const :format_valid, T::Boolean, default: false
      const :error, String, default: ""

      sig { returns(T::Boolean) }
      attr_accessor :valid

      sig { returns(String) }
      attr_accessor :error
    end
  end
end
