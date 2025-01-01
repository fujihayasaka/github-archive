# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

class Conduit::OrgFeedFilterTest < GitHub::TestCase
  fixtures do
    Flipper[:feeds_v2].enable
    Flipper[:conduit_org_feeds].enable
    @user = create(:user)
  end

  context "#class methods" do
    test "validates group name" do
      assert Conduit::OrgFeedFilter.is_valid_group?("Releases")
      refute Conduit::OrgFeedFilter.is_valid_group?("Announcements")
    end

    test "get values with all filters enabled" do
      assert Conduit::OrgFeedFilter.include_all_filter.all? { |_k, v| v == true }
    end

    test "get values with all filters disabled" do
      assert Conduit::OrgFeedFilter.exclude_all_filter.all? { |_k, v| v == false }
    end

    test "get only available filter to user" do
      expected_groups = Conduit::OrgFeedFilter
        .available_groups(viewer: @user)
        .transform_values { |_v| true }

      assert_equal expected_groups, Conduit::OrgFeedFilter.include_available_filter(@user)
    end
  end

  context "#instance methods" do
    test "initialize with filter" do
      values = { "Releases": true }
      filter = Conduit::OrgFeedFilter.new(values, viewer: @user)

      assert_equal true, filter.values["Releases"]
    end

    test "initialize without filter" do
      filter = Conduit::OrgFeedFilter.new(nil, viewer: @user)

      assert_equal true, filter.values["Releases"]
    end

    test "includes all filters" do
      filter = Conduit::OrgFeedFilter.new(nil, viewer: @user)
      filter.include_all!

      assert filter.values.all? { |_k, v| v == true }
    end

    test "excludes all filters" do
      filter = Conduit::OrgFeedFilter.new(nil, viewer: @user)
      filter.exclude_all!

      assert filter.values.all? { |_k, v| v == false }
    end

    test "returns true if all filters are enabled" do
      filter = Conduit::OrgFeedFilter.new(nil, viewer: @user)
      filter.include_all!

      assert filter.include_all?
    end

    test "returns true if filter group is enabled" do
      filter = Conduit::OrgFeedFilter.new({ "Releases": true, "Posts": true, "InvalidGroup": true }, viewer: @user)

      assert filter.includes_group?("Releases")
      refute filter.includes_group?("Posts")
      refute filter.includes_group?("InvalidGroup")
    end

    test "returns values with specific groups enabled" do
      filter = Conduit::OrgFeedFilter.new({ "Releases": true }, viewer: @user)
      values = filter.with_groups(["Repositories"])

      assert values["Releases"]
      assert values["Repositories"]
      refute values["Posts"]
    end

    test "returns values with specific groups disabled" do
      filter = Conduit::OrgFeedFilter.new({ "Releases": true, "Repositories": true }, viewer: @user)
      values = filter.without_groups(["Repositories"])

      assert values["Releases"]
      refute values["Repositories"]
    end

    test "validates if item is included in filter" do
      owner = create(:user, login: "owner")
      repo = create(:repository, owner: owner, from_example: :simple)
      release = create(:release, author: owner, repository: repo)
      included_twirp_item = build(:twirp_conduit_release_feed_item, release: release)
      excluded_twirp_item = build(:twirp_conduit_added_to_list_feed_item)

      filter = Conduit::OrgFeedFilter.new({ "Releases": true }, viewer: @user)
      assert filter.include_item?(included_twirp_item)
      refute filter.include_item?(excluded_twirp_item)
    end

    test "returns correct protobuf event types" do
      filter = Conduit::OrgFeedFilter.new({ "Releases": true }, viewer: @user)
      assert_equal Conduit::OrgFeedFilter::GROUP_TO_EVENT_TYPES[:Releases], filter.event_types

      filter = Conduit::OrgFeedFilter.new({ "Releases": true, "Repositories": true }, viewer: @user)
      assert_equal Conduit::OrgFeedFilter::GROUP_TO_EVENT_TYPES[:Releases] + Conduit::OrgFeedFilter::GROUP_TO_EVENT_TYPES[:Repositories], filter.event_types
    end
  end
end
