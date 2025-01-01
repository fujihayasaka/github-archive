# typed: strict
# frozen_string_literal: true

module SecretScanning::Encryption::LoginCredentialsCryptoHelper
  extend T::Sig
  extend T::Helpers
  include Kernel

  ERROR_MESSAGE_FAILED_TO_DECRYPT = "Failed to decrypt secret scanning value with configured encryption keys"
  ERROR_MESSAGE_NO_ENCRYPTION_KEY_CONFIGURED = "No secret scanning encryption key found"
  ERROR_MESSAGE_INVALID_PAYLOAD_FORMAT = "Invalid payload format"
  AUTH_TAG_SIZE = 16

  # encrypts and base64 encodes a given string using the secret scanning encryption key configuration
  sig { params(plaintext: String, encryption_key: T.nilable(String)).returns(String) }
  def encrypt_password(plaintext, encryption_key: nil)
    latest_key = encryption_key.present? ? encryption_key : try_get_login_credential_encryption_keys.first
    iv = OpenSSL::Random.random_bytes(12)

    aes = OpenSSL::Cipher::AES.new(128, :GCM)
    aes.encrypt
    aes.key = latest_key
    aes.iv = iv
    aes.auth_data = ""

    blob = iv + aes.update(plaintext) + aes.final + aes.auth_tag(AUTH_TAG_SIZE)
    Base64.strict_encode64(blob)
  end

  # decrypts a given base64 encoded string using the secret scanning encryption key configuration
  sig { params(encoded_ciphertext: String).returns(String) }
  def decrypt_password(encoded_ciphertext)
    ciphertext = Base64.strict_decode64(encoded_ciphertext)
    aes = OpenSSL::Cipher::AES.new(128, :GCM)

    if ciphertext.size < AUTH_TAG_SIZE + aes.iv_len
      raise ArgumentError, ERROR_MESSAGE_INVALID_PAYLOAD_FORMAT
    end

    iv = ciphertext.byteslice(0, aes.iv_len)

    aes.decrypt
    aes.iv = iv
    aes.auth_tag = ciphertext.byteslice(-AUTH_TAG_SIZE, AUTH_TAG_SIZE)

    ct_offset = aes.iv_len
    ct_size = ciphertext.bytesize - aes.iv_len - AUTH_TAG_SIZE
    ct = ciphertext.byteslice(ct_offset, ct_size)

    try_get_login_credential_encryption_keys.each do |key|
      aes.key = key
      plaintext = aes.update(ct) + aes.final

      return plaintext
    rescue OpenSSL::Cipher::CipherError => e
      # this is a no-op, we just want to try all keys
    end

    raise ArgumentError, ERROR_MESSAGE_FAILED_TO_DECRYPT
  end

  private

  sig { returns(T::Array[String]) }
  def try_get_login_credential_encryption_keys
    raise ArgumentError, ERROR_MESSAGE_NO_ENCRYPTION_KEY_CONFIGURED if GitHub.secret_scanning_v1_api_encryption_keys_delimited.blank?
    GitHub.secret_scanning_v1_api_encryption_keys_delimited.split(";")
  end
end
