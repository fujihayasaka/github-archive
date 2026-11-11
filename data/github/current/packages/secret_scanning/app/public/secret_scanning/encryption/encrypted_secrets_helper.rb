# typed: strict
# frozen_string_literal: true

module SecretScanning::Encryption::EncryptedSecretsHelper
  # Decrypts an encrypted token string and returns the raw secret, or nil on failure.
  # Handles UTF-8 scrubbing and emits dogstats metrics. Callers can pass an optional
  # source tag for metrics attribution (e.g. "public_monitoring").
  sig { params(encrypted_token: T.untyped, source: T.nilable(String)).returns(T.nilable(String)) }
  def self.decrypt_raw_secret(encrypted_token, source: nil)
    tags = source ? ["source:#{source}"] : []

    if encrypted_token.blank?
      GitHub.dogstats.increment("secret_scanning.api.encrypted_secret.decrypt", tags: tags + ["success:false", "error:no_encrypted_token"])
      return nil
    end

    begin
      raw_secret = SecretScanning::Encryption::EncryptedSecretsCryptoHelper.decrypt_encrypted_secret(encrypted_token)
      if raw_secret.present?
        GitHub.dogstats.increment("secret_scanning.api.encrypted_secret.decrypt", tags: tags + ["success:true"])
        raw_secret.dup.force_encoding("UTF-8").scrub
      else
        GitHub.dogstats.increment("secret_scanning.api.encrypted_secret.decrypt", tags: tags + ["success:false", "error:blank_decrypted_secret"])
        nil
      end
    rescue ArgumentError => e
      GitHub.dogstats.increment("secret_scanning.api.encrypted_secret.decrypt", tags: tags + ["success:false", "error:#{e.message}"])
      nil
    end
  end

  # Attempts to populate token.raw_secret with the value decrypted from token.encrypted_token, if present
  sig { params(token: T.any(GitHub::TokenScanning::Service::Token, SecretScanning::PublicMonitoringAlert)).void }
  def self.set_raw_secret_from_encrypted_secret(token)
    raw_secret = decrypt_raw_secret(token.encrypted_token)
    return if raw_secret.nil?

    token.raw_secret = raw_secret
    if token.is_base64_encoded
      token.decoded_base64_raw_secret = Base64.decode64(raw_secret)
    end
  end

  # DEPRECATED: Use the static class version instead.
  sig { params(token: T.any(GitHub::TokenScanning::Service::Token, SecretScanning::PublicMonitoringAlert)).void }
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
