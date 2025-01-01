# typed: strict
# frozen_string_literal: true

class SecretScanning::Encryption::EncryptedSecretsCryptoHelper
  extend T::Sig
  extend T::Helpers
  include Kernel

  ERROR_MESSAGE_NO_ENCRYPTION_KEY_CONFIGURED = "No secret scanning encryption key found for encrypted secrets"

  # encrypts a given bytestring using the secret scanning encryption key configuration
  sig { params(plaintext: String, encryption_key: T.nilable(String)).returns(String) }
  def self.encrypt_secret(plaintext, encryption_key: nil)
    latest_key_encoded = encryption_key.present? ? encryption_key : try_get_encrypted_secret_encryption_keys.last
    latest_key = Base64.strict_decode64(T.must(latest_key_encoded))
    SecretScanning::Encryption::CryptoHelper.encrypt(plaintext, latest_key)
  end

  # decrypts a given bytestring using the secret scanning encryption key configuration
  sig { params(ciphertext: String).returns(String) }
  def self.decrypt_encrypted_secret(ciphertext)
    keys = T::Array[String].new
    try_get_encrypted_secret_encryption_keys.each do |key|
      keys << Base64.strict_decode64(key)
    end

    SecretScanning::Encryption::CryptoHelper.decrypt(ciphertext, keys)
  end

  sig { returns(T::Array[String]) }
  private_class_method def self.try_get_encrypted_secret_encryption_keys
    raise ArgumentError, ERROR_MESSAGE_NO_ENCRYPTION_KEY_CONFIGURED if GitHub.secret_scanning_encrypted_secrets_delimited_shared_transit_keys.blank?
    GitHub.secret_scanning_encrypted_secrets_delimited_shared_transit_keys.split(";")
  end
end
