# typed: strict
# frozen_string_literal: true

module SecretScanning::Encryption::EncryptedSecretsHelper
  # Attempts to populate token.raw_secret with the value decrypted from token.encrypted_token, if present
  sig { params(token: GitHub::TokenScanning::Service::Token).void }
  def self.set_raw_secret_from_encrypted_secret(token)
    if token.encrypted_token.blank?
      GitHub.dogstats.increment("secret_scanning.api.encrypted_secret.decrypt", tags: ["success:false", "error:no_encrypted_token"])
      return
    end

    begin
      raw_secret = SecretScanning::Encryption::EncryptedSecretsCryptoHelper.decrypt_encrypted_secret(token.encrypted_token)
      if raw_secret.present?
        # Custom patterns containing `(.*)` can match an individual byte of UTF-8 for some reason,
        # which matches the first byte of chars like ø, causing invalid UTF-8 bytes.
        # GitHub::JSON encoding correctly replaces these, but emits a warning to Sentry when replacement happens.
        # So we're gonna manually do the replacement ourselves to prevent Sentry warnings.
        token.raw_secret = raw_secret.dup.force_encoding("UTF-8").scrub
        GitHub.dogstats.increment("secret_scanning.api.encrypted_secret.decrypt", tags: ["success:true"])
        if token.is_base64_encoded
          token.decoded_base64_raw_secret = Base64.decode64(raw_secret)
        end
      else
        GitHub.dogstats.increment("secret_scanning.api.encrypted_secret.decrypt", tags: ["success:false", "error:blank_decrypted_secret"])
      end
    rescue ArgumentError => e
      GitHub.dogstats.increment("secret_scanning.api.encrypted_secret.decrypt", tags: ["success:false", "error:#{e.message}"])
    end
  end

  # DEPRECATED: Use the static class version instead.
  sig { params(token: GitHub::TokenScanning::Service::Token).void }
  def set_raw_secret_from_encrypted_secret(token)
    SecretScanning::Encryption::EncryptedSecretsHelper.set_raw_secret_from_encrypted_secret(token)
  end

  sig { params(tokens: T::Array[GitHub::TokenScanning::Service::Token]).void }
  def set_raw_secrets_from_encrypted_secrets(tokens)
    tokens.each do |token|
      set_raw_secret_from_encrypted_secret(token)
    end
  end

end
