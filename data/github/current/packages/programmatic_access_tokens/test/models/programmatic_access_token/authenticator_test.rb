# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/authnd_client_helpers"

class ProgrammaticAccessToken::AuthenticatorTest < GitHub::TestCase
  include AuthndClientTestHelpers

  fixtures do
    @pat = create(:user_programmatic_access)
    @token = ProgrammaticAccessTokens.domain.generate(@pat.user_id, @pat.id).value
  end

  setup do
    setup_authnd_stub
  end

  teardown do
    remove_authnd_stub
  end

  def described_class
    ::ProgrammaticAccessToken::Authenticator
  end

  test "returns a success result when credentials are found" do
    stub_authnd_programmatic_access_token(@pat, @token)

    result = described_class.perform(@token)
    assert_predicate result, :success?
    assert_kind_of Integer, result.value
    assert_nil result.error
  end

  test "returns a failed result if authnd returns a failed result" do
    stub_authnd_programmatic_access_token(@pat, @token, result: :RESULT_FAILED_CREDENTIAL_INVALID)
    result = described_class.perform(@token)
    assert_predicate result, :failed?
    assert_nil result.value
  end

  test "returns a failed result if an exception is raised during the process" do
    stub_authnd_programmatic_access_token(@pat, @token, raise_with: Faraday::ClientError.new("error"))
    result = described_class.perform(@token)
    assert_predicate result, :failed?
    assert_equal result.error, "error"
    assert_nil result.value
  end
end
