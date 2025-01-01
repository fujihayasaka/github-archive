# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryTempCloneTokenTest < GitHub::TestCase
  fixtures do
    @user  = create(:paid_user)
    @repo  = create(:private_repository, :minimal, owner: @user)
  end

  test "creates a valid token with correct scope" do
    expire_time = 5.minutes.from_now

    expected_token_options = {
      scope: "TemporaryCloneURL:#{@repo.id}:read",
      expires: expire_time,
    }

    expected_token = @user.signed_auth_token(expected_token_options)

    temp_clone_token = @repo.temp_clone_token(@user, expires: expire_time)

    assert_equal temp_clone_token, expected_token
  end
end
