# typed: strict
# frozen_string_literal: true

class SecretScanning::Encryption::EncryptedUserContentCryptoHelper
  extend T::Sig
  extend T::Helpers
  include Kernel

  ERROR_MESSAGE_NO_ENCRYPTION_KEY_CONFIGURED = "No secret scanning encryption key found for encrypted content"
  SALT = "scan_content"
  AES_SIZE = 256

  # encrypts a given bytestring using the secret scanning encryption key configuration
  sig do
    params(
      plaintext: String,
      created_timestamp: Time,
      id: Integer,
      encryption_key: T.nilable(String)
    ).returns(String).checked(:always).on_failure(:raise)
  end
  def self.encrypt_user_content(plaintext, created_timestamp, id, encryption_key: nil)
    latest_root_key_encoded = encryption_key.present? ? encryption_key : try_get_encrypted_content_encryption_keys.last
    latest_root_key = Base64.strict_decode64(T.must(latest_root_key_encoded))
    key = build_user_content_key(latest_root_key, created_timestamp, id)

    SecretScanning::Encryption::CryptoHelper.encrypt(plaintext, key)
  end

  # decrypts a given bytestring using the secret scanning encryption key configuration
  sig do
    params(
      ciphertext: String,
      created_timestamp: Time,
      id: Integer
    ).returns(String).checked(:always).on_failure(:raise)
  end
  def self.decrypt_encrypted_user_content(ciphertext, created_timestamp, id)
    keys = T::Array[String].new
    try_get_encrypted_content_encryption_keys.each do |key|
      root_key = Base64.strict_decode64(key)
      key = build_user_content_key(root_key, created_timestamp, id)
      keys << key
    end
    SecretScanning::Encryption::CryptoHelper.decrypt(ciphertext, keys)
  end

  sig { returns(T::Array[String]) }
  private_class_method def self.try_get_encrypted_content_encryption_keys
    raise ArgumentError, ERROR_MESSAGE_NO_ENCRYPTION_KEY_CONFIGURED if GitHub.secret_scanning_user_content_delimited_encryption_root_keys.blank?
    GitHub.secret_scanning_user_content_delimited_encryption_root_keys.split(";")
  end

  # derives the user content key from the encryption key, created timestamp, and id
  sig { params(encryption_key: String, created_timestamp: Time, id: Integer).returns(String) }
  private_class_method def self.build_user_content_key(encryption_key, created_timestamp, id)
    anti_nonce_exhaustion_data = id.to_s + created_timestamp.strftime("%Y-%m-%d")
    key = OpenSSL::KDF::hkdf(encryption_key, salt: SALT, info: anti_nonce_exhaustion_data, length: AES_SIZE / 8, hash: OpenSSL::Digest::SHA256.new)
  end
end
