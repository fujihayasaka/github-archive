# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class CodeSecurityFailureReason < FailureReason
    sig { override.returns(String) }
    def to_s
      SecurityProduct::CodeSecurity.error_to_message(symbol)
    end
  end
end
