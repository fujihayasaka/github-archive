# typed: true
# frozen_string_literal: true

require "test_helper"

class TheGhostUserTest < GitHub::TestCase
  test "match login" do
    assert_equal "ghost", GitHub.ghost_user_login
    assert_equal "ghost", User.ghost.login
  end

  test "cannot fork" do
    repo = create(:repository)
    refute User.ghost.can_fork? repo
  end

  test "disable notifications when it's created" do
    assert GitHub.newsies.settings(User.ghost).participating_settings.empty?,
      "Expected participating notifications to be empty"
    assert GitHub.newsies.settings(User.ghost).subscribed_settings.empty?,
      "Expected subscribed notifications to be empty"
  end

  if GitHub.enterprise?
    test "is created with random passwords" do
      assert ghost1 = User.ghost
      refute ghost1.new_record?
      User.ghost.destroy
      assert ghost2 = User.create_ghost
      refute ghost2.new_record?

      refute_equal ghost1.password_hash, ghost2.password_hash
    end
  end
end
