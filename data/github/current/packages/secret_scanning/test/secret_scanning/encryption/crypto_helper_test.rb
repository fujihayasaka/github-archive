# typed: true
# frozen_string_literal: true
require_relative "../../../../../test/test_helper"

class CryptoHelperTest < GitHub::TestCase
  fixtures do
    @mock_iv = "123456789012"
    @mock_tag = "1234567890123456"
    @key = "1jraR8/7NcrmianjGYhrs37veyvqR2fBsHgpHUnQsLE="
    @decoded_key = Base64.strict_decode64(T.must(@key))
    @decryption_keys = Array(@decoded_key)
  end

  test "successfully encrypts and decrypts a value" do
    ciphertext = SecretScanning::Encryption::CryptoHelper.encrypt("test", @decoded_key)
    decrypted = SecretScanning::Encryption::CryptoHelper.decrypt(ciphertext, @decryption_keys)
    assert_equal decrypted, "test"
  end


  test "fails to encrypt a value with an invalid encryption key" do
    invalid_key = "eeee"
    assert_raises(ArgumentError) do
      decoded_invalid_key = Base64.strict_decode64(T.must(invalid_key))
      SecretScanning::Encryption::CryptoHelper.encrypt("test", decoded_invalid_key)
    end
  end

  test "fails to decrypt a value encrypted with a different encryption key" do
    invalid_key = "lvc3YAJ+GpqlogdcszhjEkRSQXnqEiabu/hkk/faLh8="
    decoded_invalid_key = Base64.strict_decode64(T.must(invalid_key))
    ciphertext = SecretScanning::Encryption::CryptoHelper.encrypt("test", decoded_invalid_key)

    error = assert_raises(ArgumentError) do
      SecretScanning::Encryption::CryptoHelper.decrypt(ciphertext, @decryption_keys)
    end

    assert_equal SecretScanning::Encryption::CryptoHelper::ERROR_MESSAGE_FAILED_TO_DECRYPT, error.message
  end


  test "fails to decrypt a value when invalid format" do
    error = assert_raises(ArgumentError) do
      SecretScanning::Encryption::CryptoHelper.decrypt("tooshort", @decryption_keys)
    end

    assert_equal SecretScanning::Encryption::CryptoHelper::ERROR_MESSAGE_INVALID_PAYLOAD_FORMAT, error.message
  end
end
