# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::BlockTest < GitHub::TestCase
  fixtures do
    @actor = create(:staff_admin_user)
    @user = create(:user)
  end

  test "users can be blocked and unblocked" do
    refute GitHubModels::Block.blocked?(@user)
    assert GitHubModels::Block.block!(actor: @actor, user: @user, reason: "bad user")
    assert GitHubModels::Block.blocked?(@user)
    GitHubModels::Block.unblock!(actor: @actor, user: @user, reason: "not so bad")
    refute GitHubModels::Block.blocked?(@user)
  end

  test "does not block hammy users" do
    refute GitHubModels::Block.blocked?(@user)
    @user.mark_as_hammy

    refute GitHubModels::Block.block!(actor: @actor, user: @user, reason: "bad user")
    refute GitHubModels::Block.blocked?(@user)
  end

  test "does not block trusted users" do
    refute GitHubModels::Block.blocked?(@user)
    @user.settings.set!(:trust_tier, "1")

    refute GitHubModels::Block.block!(actor: @actor, user: @user, reason: "bad user")
    refute GitHubModels::Block.blocked?(@user)
  end
end unless GitHub.enterprise? # In GHES, all users are trusted, so no blocks will succeed
