# typed: true
# frozen_string_literal: true

require "test_helper"

class WithOauthTokenTest < GitHub::TestCase
  fixtures do
    @user = create :user
    @oauth_app = make_oauth_app(@user)

    @oauth_app_access = make_oauth(@user, [:repo], @oauth_app)
  end

  test "with_oauth_token returns user with token" do
    token = @oauth_app_access.reset_token
    result = User.with_oauth_token(token)
    refute_nil result

    result = User.with_oauth_token("invalid#{token}")
    assert_nil result
  end

  test "with_oauth_token uses OauthAccess.with_active_token to find accesses" do
    token = @oauth_app_access.reset_token
    OauthAccess.expects(:with_active_token).returns(@oauth_app_access)

    result = User.with_oauth_token(token)
    refute_nil result
  end
end
