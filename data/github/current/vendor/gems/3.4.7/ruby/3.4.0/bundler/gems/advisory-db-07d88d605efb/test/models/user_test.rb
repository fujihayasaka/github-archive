# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "user returns `auto` as color_mode if no color_mode exists" do
    user = create :user
    user.color_mode = "light"
    user.save!
    user.reload
    assert_equal "light", user.color_mode

    user.color_mode = "auto"
    user.save!
    user.reload
    assert_equal "auto", user.color_mode

    user.color_mode = "dark"
    user.save!
    user.reload
    assert_equal "dark", user.color_mode

    user.color_mode = nil
    user.save!
    user.reload
    assert_equal "auto", user.color_mode
  end

  test "calculates and returns avatar_url" do
    user = create :user
    assert_equal "https://github.com/#{user.login}.png", user.avatar_url
  end

  test "calculates and returns email" do
    user = create :user
    assert_equal "#{user.login}@github.com", user.email
  end
end
