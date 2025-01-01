# typed: true
# frozen_string_literal: true

require "test_helper"

class AuditLogSinkConfigurationTest < GitHub::TestCase
  test "identifies zero-width spaces in splunk user input" do
    splunk = AuditLogSplunkSinkConfiguration.new(
      domain: "Darcy​With‍Invisible‌Joins",
      port: 8088,
      encrypted_token: "SUPER-ENCRYPTED",
      key_id: "SUPER-SECURE_KEY",
    )
    assert splunk.input_contains_whitespaces?
  end

  test "returns false if splunk user input does not include zero-width spaces" do
    splunk = AuditLogSplunkSinkConfiguration.new(
      domain: "DarcyWithoutInvisibleJoins",
      port: 8088,
      encrypted_token: "SUPER-ENCRYPTED",
      key_id: "SUPER-SECURE_KEY",
    )
    refute splunk.input_contains_whitespaces?
  end
end
