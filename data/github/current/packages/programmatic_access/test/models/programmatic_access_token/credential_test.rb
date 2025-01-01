# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/authnd_client_helpers"

class ProgrammaticAccessToken::CredentialTest < GitHub::TestCase
  include AuthndClientTestHelpers

  fixtures do
    @pat = create(:user_programmatic_access)
  end

  setup do
    setup_authnd_stub
  end

  teardown do
    remove_authnd_stub
  end

  test "converts protobuff attribute lists to credential" do
    protobuff = stub_authnd_credential_attribute_list(id: 1)
    credential = ProgrammaticAccessToken::Credential
      .new_from_protobuff(protobuff)

    assert_equal 1, credential.id
    assert_nil credential.expires_at
    assert_equal "12345678", credential.token_last_eight
  end

  test "converts protobuff attribute lists to credentials with expiration" do
    expiration_time = 5.days.from_now.utc

    protobuff = stub_authnd_credential_attribute_list(
      id: 1,
      expires_at_utc: expiration_time
    )

    credential = ProgrammaticAccessToken::Credential
      .new_from_protobuff(protobuff)

    assert_equal 1, credential.id
    assert_same_time expiration_time, credential.expires_at
    assert_equal "12345678", credential.token_last_eight
  end
end
