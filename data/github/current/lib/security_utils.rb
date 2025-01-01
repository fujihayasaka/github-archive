# typed: true
# frozen_string_literal: true

module SecurityUtils

  autoload :UrlSafeMessageVerifier, "security_utils/url_safe_message_verifier"

  # Constant time string comparison.
  def self.secure_compare(a, b)
    unless a.is_a?(String) && b.is_a?(String)
      raise ArgumentError, "both arguments must be String values"
    end
    Rack::Utils.secure_compare(a, b)
  end
end
