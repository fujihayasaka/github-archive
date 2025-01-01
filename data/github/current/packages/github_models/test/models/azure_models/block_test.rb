# typed: true
# frozen_string_literal: true

require "test_helper"

class AzureModelsBlockTest < GitHub::TestCase

  fixtures do
    @actor = create(:staff_admin_user)
    @user = create(:user)
  end

  test "users can be blocked and unblocked" do
    refute AzureModels::Block.blocked?(@user)
    AzureModels::Block.block!(actor: @actor, user: @user, reason: "bad user")
    assert AzureModels::Block.blocked?(@user)
    AzureModels::Block.unblock!(actor: @actor, user: @user, reason: "not so bad")
    refute AzureModels::Block.blocked?(@user)
  end

  test "does not block hammy users" do
    refute AzureModels::Block.blocked?(@user)
    @user.mark_as_hammy

    AzureModels::Block.block!(actor: @actor, user: @user, reason: "bad user")
    refute AzureModels::Block.blocked?(@user)
  end

  test "does not block trusted users" do
    refute AzureModels::Block.blocked?(@user)
    @user.settings.set!(:trust_tier, "1")

    AzureModels::Block.block!(actor: @actor, user: @user, reason: "bad user")
    refute AzureModels::Block.blocked?(@user)
  end
end unless GitHub.enterprise? # In GHES, all users are trusted, so no blocks will succeed
