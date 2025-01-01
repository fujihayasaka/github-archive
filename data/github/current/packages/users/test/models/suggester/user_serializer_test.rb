# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"

class SuggesterUserSerializerTest < GitHub::TestCase
  include DependabotGithubAppHelper

  fixtures do
    @user = create(:user)
  end

  setup do
    @format = Suggester::UserSerializer.new(viewer: @user, get_avatars: true)
  end

  def dependabot_bot
    make_trusted_oauth_apps_owner
    reset_dependabot_github_app_memoization

    GitHub.stubs(dependency_graph_enabled?: true)
    GitHub.stubs(dependabot_enabled?: true)
    create(:dependabot_integration).bot
  end

  test "dumps user attributes" do
    expected = {
      type: "user",
      id: @user.id,
      login: @user.login,
      name: @user.profile_name || "",
      avatarUrl: @user.primary_avatar_url,
    }
    result = @format.dump(@user)
    assert_equal expected, result
  end

  test "maps user attributes as a proc" do
    expected = @format.dump(@user)
    result = [@user].map(&@format).first
    assert_equal expected, result
  end

  test "dumps dependabot as dependabot" do
    bot = dependabot_bot

    expected = {
      type: "user",
      id: bot.id,
      login: "dependabot",
      name: bot.profile_name || "",
      avatarUrl: bot.primary_avatar_url,
    }

    assert_equal expected, @format.dump(bot)
  end

  test "dumps a random bot normally" do
    bot = create(:integration, name: "simple-ci").bot

    expected = {
      type: "user",
      id: bot.id,
      login: bot.display_login,
      name: bot.profile_name || "",
      avatarUrl: bot.primary_avatar_url,
    }

    assert_equal expected, @format.dump(bot)
  end
end
