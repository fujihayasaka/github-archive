# typed: true
# frozen_string_literal: true

require "test_helper"

class FeedFilterSettingsTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
  end

  test "requires user" do
    settings = FeedFilterSettings.new(user: nil)
    refute_predicate settings, :valid?
    assert_equal ["User must exist", "User can't be blank"], settings.errors.full_messages
  end
end
