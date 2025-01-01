# typed: strict
# frozen_string_literal: true

class SecretScanning::Encryption::CryptoHelper
  extend T::Sig
  extend T::Helpers
  include Kernel

  ERROR_MESSAGE_FAILED_TO_DECRYPT = "Failed to decrypt encrypted secrets/content with configured encryption keys"
  ERROR_MESSAGE_INVALID_PAYLOAD_FORMAT = "Invalid payload format"
  AUTH_TAG_SIZE = 16

  # encrypts a given bytestring using the provided *decoded* key
  sig { params(plaintext: String, decoded_key: T.nilable(String)).returns(String) }
  def self.encrypt(plaintext, decoded_key)
    iv = OpenSSL::Random.random_bytes(12)

    aes = OpenSSL::Cipher::AES.new(256, :GCM)
    aes.encrypt
    aes.key = decoded_key
    aes.iv = iv
    aes.auth_data = ""

    blob = iv + aes.update(plaintext) + aes.final + aes.auth_tag(AUTH_TAG_SIZE)
  end


  # decrypts a given bytestring using the provided *decoded* key
  sig { params(ciphertext: String, decoded_keys: T::Array[String]).returns(String) }
  def self.decrypt(ciphertext, decoded_keys)
    aes = OpenSSL::Cipher::AES.new(256, :GCM)

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

    decoded_keys.each do |key|
      aes.key = key

      plaintext = aes.update(ct) + aes.final
      return plaintext
    rescue OpenSSL::Cipher::CipherError => e
      # this is a no-op, we just want to try all keys
    end

    raise ArgumentError, ERROR_MESSAGE_FAILED_TO_DECRYPT
  end
end
