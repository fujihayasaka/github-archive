# typed: true
# frozen_string_literal: true
require_relative "../../../../../test/test_helper"

class LoginCredentialsCryptoHelperTest < GitHub::TestCase
  include SecretScanning::Encryption::LoginCredentialsCryptoHelper

  fixtures do
    @mock_iv = "123456789012"
    @mock_tag = "1234567890123456"
  end

  test "successfully encrypts and decrypts a value" do
    ciphertext = encrypt_password("test")
    decrypted = decrypt_password(ciphertext)
  end

  test "successfully decrypts a value encrypted with a known older key" do
    old_key = GitHub.secret_scanning_v1_api_encryption_keys_delimited.split(";").last
    ciphertext = encrypt_password("test", encryption_key: old_key)
    decrypted = decrypt_password(ciphertext)
  end

  test "fails to decrypt a value encrypted with an invalid encryption key" do
    invalid_key = "eeeeeeeeeeeeeeee"
    ciphertext = encrypt_password("test", encryption_key: invalid_key)

    error = assert_raises(ArgumentError) do
      decrypt_password(ciphertext)
    end

    assert_equal ERROR_MESSAGE_FAILED_TO_DECRYPT, error.message
  end

  test "fails to encrypt a value when encryption key not configured" do
    GitHub.stubs(:secret_scanning_v1_api_encryption_keys_delimited).returns(nil)

    error = assert_raises(ArgumentError) do
      ciphertext = encrypt_password("test")
    end

    assert_equal ERROR_MESSAGE_NO_ENCRYPTION_KEY_CONFIGURED, error.message
  end

  test "fails to decrypt a value when encryption key not configured" do
    GitHub.stubs(:secret_scanning_v1_api_encryption_keys_delimited).returns(nil)

    error = assert_raises(ArgumentError) do
      text = @mock_iv + "test" + @mock_tag
      encoded = Base64.strict_encode64(text)
      decrypt_password(encoded)
    end

    assert_equal ERROR_MESSAGE_NO_ENCRYPTION_KEY_CONFIGURED, error.message
  end

  test "fails to decrypt a value when invalid format" do
    GitHub.stubs(:secret_scanning_v1_api_encryption_keys_delimited).returns(nil)

    error = assert_raises(ArgumentError) do
      decrypt_password("tooshort")
    end

    assert_equal ERROR_MESSAGE_INVALID_PAYLOAD_FORMAT, error.message
  end
end
