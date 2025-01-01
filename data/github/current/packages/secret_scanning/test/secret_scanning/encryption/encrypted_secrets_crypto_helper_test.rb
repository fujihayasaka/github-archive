# typed: true
# frozen_string_literal: true

require_relative "../../../../../test/test_helper"

class EncryptedSecretsCryptoHelperTest < GitHub::TestCase
  Helper = SecretScanning::Encryption::EncryptedSecretsCryptoHelper

  fixtures do
    @mock_iv = "123456789012"
    @mock_tag = "1234567890123456"
  end

  test "successfully encrypts and decrypts a value" do
    ciphertext = Helper.encrypt_secret("test")
    decrypted = Helper.decrypt_encrypted_secret(ciphertext)
    assert_equal decrypted, "test"
  end

  test "successfully decrypts a value encrypted with a known older key" do
    old_key = GitHub.secret_scanning_encrypted_secrets_delimited_shared_transit_keys.split(";").first
    ciphertext = Helper.encrypt_secret("test", encryption_key: old_key)
    decrypted = Helper.decrypt_encrypted_secret(ciphertext)
    assert_equal decrypted, "test"
  end

  test "fails to encrypt a value with an invalid encryption key" do
    invalid_key = "eeeee"
    assert_raises(ArgumentError) do
      Helper.encrypt_secret("test", encryption_key: invalid_key)
    end
  end

  test "fails to decrypt a value encrypted with an encryption key not in the delimited key list" do
    invalid_key = "q86nP3MBZaN2B8eIX5ZwzoEYIAlyL2YI87wR52fmI9E="
    ciphertext = Helper.encrypt_secret("test", encryption_key: invalid_key)

    error = assert_raises(ArgumentError) do
      Helper.decrypt_encrypted_secret(ciphertext)
    end

    assert_equal SecretScanning::Encryption::CryptoHelper::ERROR_MESSAGE_FAILED_TO_DECRYPT, error.message
  end

  test "fails to encrypt a value when encryption key not configured" do
    GitHub.stubs(:secret_scanning_encrypted_secrets_delimited_shared_transit_keys).returns(nil)

    error = assert_raises(ArgumentError) do
      ciphertext = Helper.encrypt_secret("test")
    end

    assert_equal Helper::ERROR_MESSAGE_NO_ENCRYPTION_KEY_CONFIGURED, error.message
  end

  test "fails to decrypt a value when encryption key not configured" do
    GitHub.stubs(:secret_scanning_encrypted_secrets_delimited_shared_transit_keys).returns(nil)

    error = assert_raises(ArgumentError) do
      text = @mock_iv + "test" + @mock_tag
      Helper.decrypt_encrypted_secret(text)
    end

    assert_equal Helper::ERROR_MESSAGE_NO_ENCRYPTION_KEY_CONFIGURED, error.message
  end

  test "fails to decrypt a value when invalid format" do
    error = assert_raises(ArgumentError) do
      Helper.decrypt_encrypted_secret("tooshort")
    end

    assert_equal SecretScanning::Encryption::CryptoHelper::ERROR_MESSAGE_INVALID_PAYLOAD_FORMAT, error.message
  end
end
