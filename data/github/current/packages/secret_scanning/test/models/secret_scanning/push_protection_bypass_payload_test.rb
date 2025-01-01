# typed: true
# frozen_string_literal: true

require "test_helper"

class PushProtectionBypassPayloadTest < GitHub::TestCase

  test "initialize" do
    payload = SecretScanning::PushProtectionBypassPayload.new("AWS_SECRET", "abcd1234", "AWS Secret Key")
    assert_equal "AWS_SECRET", payload.token_type
    assert_equal "abcd1234", payload.token_signature
    assert_equal "AWS Secret Key", payload.token_type_label
  end

  test "encode and decode" do
    signature = "a" * 64
    payload = SecretScanning::PushProtectionBypassPayload.new("AWS_SECRET", signature, "AWS Secret Key")
    encoded = payload.to_base64
    decoded = SecretScanning::PushProtectionBypassPayload.from_base64(encoded)
    assert_equal "AWS_SECRET", decoded.token_type
    assert_equal signature, decoded.token_signature
    assert_equal "AWS Secret Key", decoded.token_type_label
  end

  test "decode with invalid payload" do
    assert_raises(ArgumentError) do
      SecretScanning::PushProtectionBypassPayload.from_base64("")
    end
    assert_raises(ArgumentError) do
      SecretScanning::PushProtectionBypassPayload.from_base64("12345")
    end
    assert_raises(ArgumentError) do
      SecretScanning::PushProtectionBypassPayload.from_base64(100)
    end
    assert_raises(ArgumentError) do
      SecretScanning::PushProtectionBypassPayload.from_base64(nil)
    end
    assert_raises(ArgumentError) do
      invalid_payload = Base64.urlsafe_encode64(JSON.generate({
        hello: "world",
        foo: "bar",
      }))
      SecretScanning::PushProtectionBypassPayload.from_base64(invalid_payload)
    end
    # signature is not 64 characters
    assert_raises(ArgumentError) do
      invalid_payload = Base64.urlsafe_encode64(JSON.generate({
        token_type: "AWS_SECRET",
        token_signature: "abcd1234",
        token_type_label: "AWS Secret Key"
      }))
      SecretScanning::PushProtectionBypassPayload.from_base64(invalid_payload)
    end
  end
end
