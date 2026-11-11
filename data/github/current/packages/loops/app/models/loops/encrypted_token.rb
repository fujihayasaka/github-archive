# typed: strict
# frozen_string_literal: true

# Public: Acts as a wrapper for a Loops token that is encrypted and encoded, to allow differentiating from
# an unencrypted + decoded token (a regular String).
class Loops::EncryptedToken < T::Struct

  sig do
    params(
      value: String,
      expiration: T.nilable(T.any(ActiveSupport::TimeWithZone, Time))
    ).returns(Loops::EncryptedToken)
  end
  def self.from(value, expiration: nil)
    new(value: value, expiration: expiration)
  end

  const :value, String
  const :expiration, T.nilable(T.any(ActiveSupport::TimeWithZone, Time))

  sig { returns(Loops::DecryptedToken) }
  def decode_and_decrypt
    decrypted_value = T.must(GitHub.decode_and_decrypt_loops_token(value))
    Loops::DecryptedToken.from(decrypted_value)
  end

  sig { returns(String) }
  def to_s
    value
  end

  sig { returns(String) }
  def authorization_header_value
    "GitHub-Bearer #{value}"
  end
end
