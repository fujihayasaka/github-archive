# typed: true
# frozen_string_literal: true

require "test_helper"

class ServerToServerToken::AuthenticatorTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
    @integration = create(:integration)
    @authenticatable = make_integration_installation(integration: @integration, target: @user)
  end

  test "returns authnd success result when authenticating a valid token" do
    token, token_value = @authenticatable.generate_token
    authnd_response = ServerToServerToken::Authenticator.perform("github/authnd", token_value)

    assert_equal(:RESULT_SUCCESS, authnd_response.result)
    assert_equal(token.authenticatable_id, authnd_response.attributes["installation.id"])
    assert_equal(token.id, authnd_response.attributes["credential.id"])
  end

  test "returns authnd failure when authenticating an invalid token" do
    token_value = "ghs_invalid_token_base64"
    authnd_response = ServerToServerToken::Authenticator.perform("github/authnd", token_value)
    assert_equal(:RESULT_FAILED_CREDENTIAL_INVALID, authnd_response.result)
  end

  test "returns authnd failure when token is not found" do
    token_value = "ghs_TrtWl0C6HEROtm2hu6JWn9yuAqM29w2gpHnp"
    authnd_response = ServerToServerToken::Authenticator.perform("github/authnd", token_value)
    assert_equal(:RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND, authnd_response.result)
  end
end
