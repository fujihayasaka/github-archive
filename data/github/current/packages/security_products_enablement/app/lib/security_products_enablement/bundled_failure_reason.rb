# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class BundledFailureReason < FailureReason
    sig { override.returns(String) }
    def to_s
      SecurityProduct::AdvancedSecurity.error_to_message(symbol)
    end
  end
end
