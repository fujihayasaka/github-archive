# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

class Conduit::FeedFilterTest < GitHub::TestCase
  fixtures do
    enable_feature_flag(:feed_posts)
    @user = create(:user)
  end

  context "#class methods" do
    test "validates group name" do
      assert Conduit::FeedFilter.is_valid_group?("Announcements")
      refute Conduit::FeedFilter.is_valid_group?("Invalid")
    end

    test "get array of user's available groups" do
      # testing only GA'ed features
      disable_feature_flag(:feeds_v2)
      disable_feature_flag(:conduit_starred_relationships_filter)
      expected_groups = Conduit::FeedFilter::FILTER_GROUPS.keys - %w[ExplicitOnly RepositoryActivity StarredRelationships]
      assert_equal expected_groups, Conduit::FeedFilter.available_groups(viewer: @user).keys
    end

    test "get values with all filters enabled" do
      assert Conduit::FeedFilter.include_all_filter.all? { |_k, v| v == true }
    end

    test "get values with all filters disabled" do
      assert Conduit::FeedFilter.exclude_all_filter.all? { |_k, v| v == false }
    end

    test "get only available filter to user" do
      expected_groups = Conduit::FeedFilter
        .available_groups(viewer: @user)
        .transform_values { |_v| true }

      assert_equal expected_groups, Conduit::FeedFilter.include_available_filter(@user)
    end
  end

  context "#instance methods" do
    test "initialize with filter" do
      values = { "Announcements": true }
      filter = Conduit::FeedFilter.new(values, viewer: @user)

      assert_equal true, filter.values["Announcements"]
    end

    test "initialize without filter" do
      filter = Conduit::FeedFilter.new(nil, viewer: @user)

      assert_equal true, filter.values["Announcements"]
    end

    test "includes all filters" do
      filter = Conduit::FeedFilter.new(nil, viewer: @user)
      filter.include_all!

      assert filter.values.all? { |_k, v| v == true }
    end

    test "excludes all filters" do
      filter = Conduit::FeedFilter.new(nil, viewer: @user)
      filter.exclude_all!

      assert filter.values.all? { |_k, v| v == false }
    end

    test "returns true if all filters are enabled" do
      filter = Conduit::FeedFilter.new(nil, viewer: @user)
      filter.include_all!

      assert filter.include_all?
    end

    test "returns true if filter group is enabled" do
      disable_feature_flag(:feed_posts)
      filter = Conduit::FeedFilter.new({ "Announcements": true, "Posts": true, "InvalidGroup": true }, viewer: @user)

      assert filter.includes_group?("Announcements")
      refute filter.includes_group?("Posts")
      refute filter.includes_group?("InvalidGroup")
    end

    test "returns values with specific groups enabled" do
      filter = Conduit::FeedFilter.new({ "Announcements": true }, viewer: @user)
      values = filter.with_groups(["Follows"])

      assert values["Announcements"]
      assert values["Follows"]
      refute values["Posts"]
    end

    test "returns values with specific groups disabled" do
      filter = Conduit::FeedFilter.new({ "Announcements": true, "Follows": true }, viewer: @user)
      values = filter.without_groups(["Follows"])

      assert values["Announcements"]
      refute values["Follows"]
    end

    test "validates if item is included in filter" do
      discussion = create(:discussion)
      included_twirp_item = build(:twirp_conduit_discussion_feed_item, discussion: discussion)
      excluded_twirp_item = build(:twirp_conduit_added_to_list_feed_item)

      filter = Conduit::FeedFilter.new({ "Announcements": true }, viewer: @user)
      assert filter.include_item?(included_twirp_item)
      refute filter.include_item?(excluded_twirp_item)
    end

    test "returns correct protobuf event types" do
      filter = Conduit::FeedFilter.new({ "Announcements": true }, viewer: @user)
      assert_equal Conduit::FeedFilter::GROUP_TO_EVENT_TYPES[:Announcements], filter.event_types

      filter = Conduit::FeedFilter.new({ "Announcements": true, "Repositories": true }, viewer: @user)
      assert_equal Conduit::FeedFilter::GROUP_TO_EVENT_TYPES[:Announcements] + Conduit::FeedFilter::GROUP_TO_EVENT_TYPES[:Repositories], filter.event_types
    end

    test "exclude starred relationships filter without feature flag" do
      disable_feature_flag(:conduit_starred_relationships_filter, @user)
      filter = Conduit::FeedFilter.new({ "StarredRelationships": true }, viewer: @user)
      refute filter.available_groups["StarredRelationships"]
    end

    test "include starred relationships filter with feature flag" do
      enable_feature_flag(:conduit_starred_relationships_filter, @user)
      filter = Conduit::FeedFilter.new({ "StarredRelationships": true }, viewer: @user)
      assert filter.available_groups["StarredRelationships"]
    end
  end
end
