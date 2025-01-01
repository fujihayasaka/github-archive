# typed: true
# frozen_string_literal: true

require "test_helper"

class GhostGitHubAppTest < GitHub::TestCase

  test "it is a singleton" do
    assert_raises(NoMethodError) do
      T.unsafe(GhostGitHubApp).new
    end

    assert GhostGitHubApp.instance == GhostGitHubApp.instance
  end

  test "it is readonly" do
    assert GhostGitHubApp.instance.readonly?
  end

  test "#name" do
    assert_equal "Deleted GitHub App", GhostGitHubApp.instance.name
  end

  test "#primary_avatar_url" do
    assert_equal User.ghost.primary_avatar_url, GhostGitHubApp.instance.primary_avatar_url
  end

  test "#preferred_avatar_url" do
    assert_equal User.ghost.primary_avatar_url(400), GhostGitHubApp.instance.preferred_avatar_url(size: 400)
  end

  test "#owner" do
    assert_equal User.ghost, GhostGitHubApp.instance.owner
  end

  test "#ghost?" do
    assert GhostGitHubApp.instance.ghost?
  end
end
