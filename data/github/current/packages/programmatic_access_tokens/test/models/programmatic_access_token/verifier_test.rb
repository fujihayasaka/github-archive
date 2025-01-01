# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/authnd_client_helpers"

class ProgrammaticAccessToken::VerifierTest < GitHub::TestCase
  include AuthndClientTestHelpers

  setup do
    setup_authnd_stub
    Failbot.reports.clear
  end

  teardown do
    remove_authnd_stub
  end

  def described_class
    ::ProgrammaticAccessToken::Verifier
  end

  test "returns a success result when credentials are found" do
    stub_authnd_programmatic_access_verify_credentials
    result = described_class.perform(["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"])
    assert_predicate result, :success?
    assert_kind_of ::Authnd::Proto::VerifyResponse, result.value.first
    assert_nil result.error
  end

  test "returns a success result if authnd returns a failed result" do
    stub_authnd_programmatic_access_verify_credentials(result: :RESULT_FAILED_CREDENTIAL_INVALID)
    result = described_class.perform(["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"])
    value = result.value.first
    assert_predicate result, :success?
    assert_equal value.result, :RESULT_FAILED_CREDENTIAL_INVALID
    refute value.is_verified
  end

  test "returns a success result if authnd returns a expired result" do
    stub_authnd_programmatic_access_verify_credentials(result: :RESULT_EXPIRED)
    result = described_class.perform(["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"])
    value = result.value.first
    assert_predicate result, :success?
    assert_equal value.result, :RESULT_EXPIRED
    refute value.is_verified
  end

  test "returns a success result if authnd verifies multiple credentials" do
    stub_authnd_programmatic_access_verify_credentials(count: 2)
    result = described_class.perform(%w(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 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))

    assert_predicate result, :success?
    assert_equal 2, result.value.size
    (result.value).each do |val|
      assert_equal val.result, :RESULT_SUCCESS
    end
  end

  test "returns a failed result if an exception is raised during the process" do
    stub_authnd_programmatic_access_verify_credentials(raise_with: Faraday::ClientError.new("error"))
    result = described_class.perform(["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"])
    assert_predicate result, :failed?
    assert_equal result.error, "error"
    assert_nil result.value
  end
end
