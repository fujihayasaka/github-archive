# typed: true
# frozen_string_literal: true

require "test_helper"

class BotAuthenticationTest < GitHub::TestCase
  fixtures do
    @user         = create(:user)
    @installation = make_integration_installation(target: @user, permissions: { "metadata" => :read })
  end

  test "generating signed auth token for a bot will include an installation" do
    Timecop.freeze do
      bot = @installation.bot
      token = bot.signed_auth_token(scope: "some_scope")

      authed_user = User.authenticate_with_signed_auth_token(
        scope: "some_scope",
        token: token,
      )

      assert_equal bot, authed_user
      assert_equal @installation, authed_user.installation
    end
  end

  test "generating signed auth token for a bot will include a scoped installation" do
    Timecop.freeze do
      repo         = create(:repository, :minimal, owner: @user)
      installation = make_scoped_integration_installation(parent: @installation, repositories: [repo])

      bot = installation.bot
      token = bot.signed_auth_token(scope: "some_scope")

      authed_user = User.authenticate_with_signed_auth_token(
        scope: "some_scope",
        token: token,
      )

      assert_equal bot, authed_user
      assert_equal installation, authed_user.installation
    end
  end
end
