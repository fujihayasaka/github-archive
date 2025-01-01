# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class SecretProtectionFailureReason < FailureReason
    sig { override.returns(String) }
    def to_s
      SecurityProduct::TokenScanning.error_to_message(symbol)
    end
  end
end
