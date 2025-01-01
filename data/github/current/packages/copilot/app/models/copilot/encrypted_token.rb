# typed: strict
# frozen_string_literal: true

# Public: Acts as a wrapper for a Copilot token that is encrypted and encoded, to allow differentiating from
# an unencrypted + decoded token (a regular String).
class Copilot::EncryptedToken < T::Struct
  extend T::Sig

  sig do
    params(
      value: String,
      expiration: T.nilable(T.any(ActiveSupport::TimeWithZone, Time))
    ).returns(Copilot::EncryptedToken)
  end
  def self.from(value, expiration: nil)
    new(value: value, expiration: expiration)
  end

  const :value, String
  const :expiration, T.nilable(T.any(ActiveSupport::TimeWithZone, Time))

  sig { returns Copilot::DecryptedToken }
  def decode_and_decrypt
    GitHub.decode_and_decrypt_capi_token(value)
  end

  sig { returns String }
  def to_s
    value
  end

  sig { returns String }
  def authorization_header_value
    "GitHub-Bearer #{value}"
  end
end
