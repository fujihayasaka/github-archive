# typed: true
# frozen_string_literal: true

require "test_helper"

class UserFeedsConfigurationDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  test "set user feed filter in user settings and for you feed filter tables" do
    included_all_filter = Conduit::FeedFilter.include_all_filter

    @user.set_for_you_feed_filter!(included_all_filter)

    filter = ForYouFeedFilterSettings.where({ user_id: @user.id }).first
    filter = T.must(filter)

    assert_equal true, filter.sponsors_enabled
    assert_equal true, filter.announcements_enabled
    assert_equal true, filter.releases_enabled
    assert_equal true, filter.stars_enabled
    assert_equal true, filter.repositories_enabled
    assert_equal true, filter.follows_enabled
    assert_equal true, filter.recommendations_enabled
  end

  test "set topic feed filter in feed filter settings table" do
    included_all_filter = Conduit::FeedFilter.include_all_filter

    @user.set_feed_filter!(true, included_all_filter)

    filter = FeedFilterSettings.where({ user_id: @user.id, is_topic: true }).first
    filter = T.must(filter)

    assert_equal true, filter.sponsors_enabled
    assert_equal true, filter.announcements_enabled
    assert_equal true, filter.releases_enabled
    assert_equal true, filter.stars_enabled
    assert_equal true, filter.repositories_enabled
    assert_equal true, filter.follows_enabled
    assert_equal true, filter.recommendations_enabled
  end

  test "updates topic feed filter settings in table" do
    included_all_filter = Conduit::FeedFilter.include_all_filter

    @user.set_feed_filter!(true, included_all_filter)

    filter = FeedFilterSettings.where({ user_id: @user.id, is_topic: true }).first
    filter = T.must(filter)

    assert_equal true, filter.sponsors_enabled
    assert_equal true, filter.announcements_enabled
    assert_equal true, filter.releases_enabled
    assert_equal true, filter.stars_enabled
    assert_equal true, filter.repositories_enabled
    assert_equal true, filter.follows_enabled
    assert_equal true, filter.recommendations_enabled

    excluded_all_filter = Conduit::FeedFilter.exclude_all_filter

    @user.set_feed_filter!(true, excluded_all_filter)

    filter = FeedFilterSettings.where({ user_id: @user.id, is_topic: true }).first
    filter = T.must(filter)

    assert_equal false, filter.sponsors_enabled
    assert_equal false, filter.announcements_enabled
    assert_equal false, filter.releases_enabled
    assert_equal false, filter.stars_enabled
    assert_equal false, filter.repositories_enabled
    assert_equal false, filter.follows_enabled
    assert_equal false, filter.recommendations_enabled
  end
end
