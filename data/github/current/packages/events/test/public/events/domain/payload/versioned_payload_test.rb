# typed: true
# frozen_string_literal: true

require "test_helper"

class VersionPayloadTest < GitHub::TestCase
  context "initialization" do
    test "sets initial payload to provided payload" do
      initial_payload = { action: "opened" }
      versioned_payload = Events::Domain::VersionedPayload.new("", { action: "opened" })
      assert_equal(initial_payload, versioned_payload.payload)
    end
  end

  context "to_h" do
    test "return nil version when requested version in invalid" do
      mock_version = "2024-09-10"
      versioned_payload = Events::Domain::VersionedPayload.new("invalid", { action: "opened" })
      assert(!versioned_payload.is_valid?)
      expected_payload = {
        version: "invalid",
        payload: nil,
        code: :RESULT_CODE_INVALID_VERSION
      }
      assert_equal(expected_payload.to_h, versioned_payload.to_h)
    end

    test "return nil version when requested version is empty" do
      versioned_payload = Events::Domain::VersionedPayload.new("", { action: "opened" })
      assert(!versioned_payload.is_valid?)
      expected_payload = {
        version: "",
        payload: nil,
        code: :RESULT_CODE_INVALID_VERSION
      }
      assert_equal(expected_payload.to_h, versioned_payload.to_h)
    end

    test "returns requested version when requested version is valid" do
      mock_version = "2022-10-11"
      Api::Versioning.expects(:usable_version?).with(mock_version).returns(true)
      versioned_payload = Events::Domain::VersionedPayload.new(mock_version, { action: "opened" })
      assert(versioned_payload.is_valid?)
      expected_payload = {
        version: "2022-10-11",
        payload: "{\"action\":\"opened\"}",
        code: :RESULT_CODE_SUCCESS
      }
      assert_equal(expected_payload, versioned_payload.to_h)
    end
  end

  context "serialize" do
    test "adds new key and serialized data to payload" do
      versioned_payload = Events::Domain::VersionedPayload.new(Api::Versioning.default_version)
      assert_equal({}, versioned_payload.payload)

      mock_serialized_issue = { id: 1, name: "test issue" }
      Api::Serializer.expects(:serialize).returns(mock_serialized_issue) # rubocop:disable GitHub/AlwaysUseApiSerializerSerialize
      mock_obj = mock
      versioned_payload.serialize(:issue, :issue_hash, mock, {})

      expected_payload = { issue: mock_serialized_issue }
      assert_equal(expected_payload, versioned_payload.payload)
    end
  end
end
