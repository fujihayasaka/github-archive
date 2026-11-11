# typed: strict
# frozen_string_literal: true

# Public: Acts as a wrapper for a Loops token that is decrypted and decoded.
class Loops::DecryptedToken < T::Struct

  sig { params(value: String).returns(Loops::DecryptedToken) }
  def self.from(value)
    new(value: value)
  end

  const :value, String

  sig { returns(String) }
  def to_s
    value
  end

  sig { returns(String) }
  def authorization_header_value
    "token #{value}"
  end
end
