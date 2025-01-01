# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Encryption::EncryptedSecretsHelper
  # Attempts to populate token.raw_secret with the value decrypted from token.encrypted_token, if present
  def set_raw_secret_from_encrypted_secret(token)
    if token.encrypted_token.blank?
      GitHub.dogstats.increment("secret_scanning.api.encrypted_secret.decrypt", tags: ["success:false", "error:no_encrypted_token"])
      return
    end

    begin
      raw_secret = SecretScanning::Encryption::EncryptedSecretsCryptoHelper.decrypt_encrypted_secret(token.encrypted_token)
      if raw_secret.present?
        token.raw_secret = raw_secret
        GitHub.dogstats.increment("secret_scanning.api.encrypted_secret.decrypt", tags: ["success:true"])
      else
        GitHub.dogstats.increment("secret_scanning.api.encrypted_secret.decrypt", tags: ["success:false", "error:blank_decrypted_secret"])
      end
    rescue ArgumentError => e
      GitHub.dogstats.increment("secret_scanning.api.encrypted_secret.decrypt", tags: ["success:false", "error:#{e.message}"])
    end
  end

  def set_raw_secrets_from_encrypted_secrets(tokens)
    tokens.each do |token|
      set_raw_secret_from_encrypted_secret(token)
    end
  end

end
