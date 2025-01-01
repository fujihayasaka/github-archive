# typed: true
# frozen_string_literal: true

require "test_helper"

class SecretScanningRawSecretTest < GitHub::TestCase
  context "#token_literal_from_secret" do
    test "returns nil if raw secret not found" do
      not_found_msgs = SecretScanning::Util::RawSecret::NOT_FOUND_MESSAGES + [nil]
      not_found_msgs.each do |msg|
        assert_nil SecretScanning::Util::RawSecret.token_literal_from_secret(msg)
      end
    end

    test "returns encoded secret" do
      raw_secret = "caf" + "😁"
      expected_encoded_secret = "caf😁"
      actual_encoded_secret = SecretScanning::Util::RawSecret.token_literal_from_secret(raw_secret)
      assert_equal expected_encoded_secret, actual_encoded_secret
    end
  end

  context "#encoded_secret" do
    test "returns UTF-8 encoded raw secret" do
      raw_secret = "caf" + "😁"

      expected_encoded_secret = "caf😁"
      actual_encoded_secret = SecretScanning::Util::RawSecret.encoded_secret(raw_secret)

      assert_equal Encoding::UTF_8, actual_encoded_secret.encoding
      assert_equal expected_encoded_secret, actual_encoded_secret
    end

    test "returns no preview message if encoded raw secret is invalid" do
      raw_secret = "AAA \x92 日本語"
      encoded_secret = SecretScanning::Util::RawSecret.encoded_secret(raw_secret)
      assert_equal Encoding::UTF_8, encoded_secret.encoding
      assert_equal SecretScanning::Util::RawSecret::NO_PREVIEW_MESSAGE, encoded_secret
    end
  end
end
