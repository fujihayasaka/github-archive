# typed: strict
# frozen_string_literal: true

# Public: Acts as a wrapper for a Copilot token that is decrypted and decoded.
class Copilot::DecryptedToken < T::Struct

  sig { params(value: String).returns(Copilot::DecryptedToken) }
  def self.from(value)
    new(value: value)
  end

  prop :value, String

  sig { returns String }
  def to_s
    value
  end

  sig { returns String }
  def authorization_header_value
    "Bearer #{value}"
  end
end
