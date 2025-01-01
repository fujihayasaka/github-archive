# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class CredentialAuthorizationSerializersTest < Api::SerializerTestCase
  include PlatformTestHelpers::InterfaceHelpers

  fixtures do
    @org                  = create :organization
    @org_member_with_cred = create :user
    @key                  = create :public_key, user: @org_member_with_cred
    @token                = make_personal_access_token(@org_member_with_cred, scopes = %w(repo))

    @org.add_member(@org_member_with_cred)

    @key_credential_auth = Organization::CredentialAuthorization.grant(
      organization: @org,
      credential: @key,
      actor: @org_member_with_cred,
    )

    @token_credential_auth = Organization::CredentialAuthorization.grant(
      organization: @org,
      credential: @token,
      actor: @org_member_with_cred,
    )

    @credential_type_display_map = {
      "OauthAccess" => "personal access token",
      "PublicKey" => "SSH key",
    }
  end

  test "credential_authorization_hash for whitelisted ssh key" do
    # accessed_at is set by the :public_key Factory
    output = credential_authorizations(@key_credential_auth)

    assert_equal @org_member_with_cred.login, output["login"]
    assert_equal @key_credential_auth.id, output["credential_id"]
    assert_equal @credential_type_display_map[@key_credential_auth.credential_type], output["credential_type"]
    assert_equal @key_credential_auth.fingerprint, output["fingerprint"]
    assert_equal @key_credential_auth.created_at, output["credential_authorized_at"]
    assert_equal @key_credential_auth.accessed_at, output["credential_accessed_at"]
  end

  test "credential_accessed_at is nil for ssh key if never accessed" do
    key = create :public_key, user: @org_member_with_cred, accessed_at: nil
    credential_auth = Organization::CredentialAuthorization.grant(
      organization: @org,
      credential: key,
      actor: @org_member_with_cred,
    )
    output = credential_authorizations(credential_auth)

    assert output.key? "credential_accessed_at"
    assert_nil output["credential_accessed_at"]
  end

  test "credential_authorization_hash for whitelisted access token" do
    # OAuth_Access factory does not set accessed_at
    accessed_at = Time.now.utc
    @token.bump!(accessed_at)

    output = credential_authorizations(@token_credential_auth)

    assert_equal @org_member_with_cred.login, output["login"]
    assert_equal @token_credential_auth.id, output["credential_id"]
    assert_equal @credential_type_display_map[@token_credential_auth.credential_type], output["credential_type"]
    assert_equal @token_credential_auth.credential.token_last_eight, output["token_last_eight"]
    assert_equal @token_credential_auth.created_at, output["credential_authorized_at"]
    assert_equal @token_credential_auth.accessed_at, output["credential_accessed_at"]
    assert_equal @token.scopes, output["scopes"]
  end

  test "credential_accessed_at is nil for oauth token if never accessed" do
    output = credential_authorizations(@token_credential_auth)

    assert output.key? "credential_accessed_at"
    assert_nil output["credential_accessed_at"]
  end

  test "credential_authorization_hash for whitelisted ssh key that was destroyed" do
    @key.destroy
    output = credential_authorizations(@key_credential_auth)

    assert_equal @org_member_with_cred.login, output["login"]
    assert_equal @key_credential_auth.id, output["credential_id"]
    assert_equal @credential_type_display_map[@key_credential_auth.credential_type], output["credential_type"]
    assert_equal @key_credential_auth.fingerprint, output["fingerprint"]
    assert_equal @key_credential_auth.created_at, output["credential_authorized_at"]
    assert output.key? "credential_accessed_at"
    assert_nil output["credential_accessed_at"]
  end

  test "handle nil actors for credential_authorization_hash when user is deleted for token" do
    output = credential_authorizations(@token_credential_auth)
    assert_equal @org_member_with_cred.login, output["login"]

    @org_member_with_cred.delete
    @token_credential_auth.reload

    output = credential_authorizations(@token_credential_auth)
    assert_nil output["login"]
  end

  test "handle nil actors for credential_authorization_hash when user is deleted for key" do
    output = credential_authorizations(@key_credential_auth)
    assert_equal @org_member_with_cred.login, output["login"]

    @org_member_with_cred.delete
    @key_credential_auth.reload

    output = credential_authorizations(@key_credential_auth)
    assert_nil output["login"]
  end
end
