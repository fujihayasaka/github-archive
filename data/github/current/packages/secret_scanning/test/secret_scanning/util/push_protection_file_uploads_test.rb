# typed: true
# frozen_string_literal: true

require "test_helper"

class PushProtectionFileUploadsTest < GitHub::TestCase
  context "#secrets_from_json" do
    test "returns empty array if secrets not present in json" do
      json_data = JSON.generate({
        foo: "bar"
      })

      secrets = SecretScanning::Util::PushProtectionFileUploads.secrets_from_json(json_data)

      assert_equal [], secrets
    end

    test "returns array of secrets parsed from JSON" do
      json_data = JSON.generate({
        "file": "foo.md",
        "secrets": [
          {
            "type": "special",
            "fingerprint": "right_thumb",
            "bypass_placeholder_ksuid": "42",
            "locations": [
              {
                "start_line": 0,
                "end_line": 1,
                "start_line_byte_position": 1,
                "end_line_byte_position": 32
              }
            ],
            "token_metadata": {
              "token_type": "FOO_KEY",
              "slug": "foo_key",
              "label": "Foo foo",
              "provider": "Foo Inc."
            }
          }
        ]
      })

      expected_locations = T.let([], T::Array[SecretScanning::Models::Location])
      expected_locations << SecretScanning::Models::Location.new(
        start_line: 0,
        end_line: 1,
        start_line_byte_position: 1,
        end_line_byte_position: 32,
        path: "foo.md"
      )

      expected_token_metadata = SecretScanning::Models::TokenMetadata.new(
        token_type: "FOO_KEY",
        slug: "foo_key",
        label: "Foo foo",
        provider: "Foo Inc."
      )

      expected_secret = SecretScanning::Models::Secret.new(
        bypass_placeholder_ksuid: "42",
        fingerprint: "right_thumb",
        locations: expected_locations,
        token_metadata: expected_token_metadata,
        type: "special")

      secrets = SecretScanning::Util::PushProtectionFileUploads.secrets_from_json(JSON.parse(json_data))

      refute_nil secrets
      assert_equal 1, secrets.length
      secret = T.must(secrets[0])

      assert_equal expected_secret.bypass_placeholder_ksuid, secret.bypass_placeholder_ksuid
      assert_equal expected_secret.type, secret.type
      assert_equal expected_secret.fingerprint, secret.fingerprint

      expected_location = T.must(expected_secret.locations[0])
      actual_location = T.must(secret.locations[0])
      assert_equal expected_location.start_line, actual_location.start_line
      assert_equal expected_location.end_line, actual_location.end_line
      assert_equal expected_location.start_line_byte_position, actual_location.start_line_byte_position
      assert_equal expected_location.end_line_byte_position, actual_location.end_line_byte_position
      assert_equal expected_location.path, actual_location.path

      assert_equal expected_secret.token_metadata.label, secret.token_metadata.label
      assert_equal expected_secret.token_metadata.provider, secret.token_metadata.provider
      assert_equal expected_secret.token_metadata.slug, secret.token_metadata.slug
      assert_equal expected_secret.token_metadata.token_type, secret.token_metadata.token_type
    end
  end
end
