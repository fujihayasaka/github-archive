# typed: true
# frozen_string_literal: true

require "test_helper"

class ForYouFeedFilterSettingsTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
  end

  test "requires user" do
    settings = ForYouFeedFilterSettings.new(user: nil)
    refute_predicate settings, :valid?
    assert_equal ["User must exist", "User can't be blank"], settings.errors.full_messages
  end

  test "require unique user" do
    settings = ForYouFeedFilterSettings.new(user: @user)
    settings.save!
    settings = ForYouFeedFilterSettings.new(user: @user)
    refute_predicate settings, :valid?
    assert_equal ["User has already been taken"], settings.errors.full_messages
  end
end
