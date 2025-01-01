# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class TwirpHelperTest < GitHub::TestCase
    TwirpItemMock = Struct.new(:action, :subject_type)
    test "#followed_action?" do
      twirp_item = TwirpItemMock.new(action: Conduit::TwirpHelper.followed_action)
      feed_item = Conduit::FeedItem.new(twirp_item, actor: nil, subject: nil)

      assert_predicate feed_item, :followed_action?
    end

    test "#sponsorable_action?" do
      twirp_item = TwirpItemMock.new(action: Conduit::TwirpHelper.sponsorable_action)
      feed_item = Conduit::FeedItem.new(twirp_item, actor: nil, subject: nil)

      assert_predicate feed_item, :sponsorable_action?
    end

    test "#starred_action?" do
      twirp_item = TwirpItemMock.new(action: Conduit::TwirpHelper.starred_action)
      feed_item = Conduit::FeedItem.new(twirp_item, actor: nil, subject: nil)

      assert_predicate feed_item, :starred_action?
    end

    test "#created_action?" do
      twirp_item = TwirpItemMock.new(action: Conduit::TwirpHelper.created_action)
      feed_item = Conduit::FeedItem.new(twirp_item, actor: nil, subject: nil)

      assert_predicate feed_item, :created_action?
    end

    test "#forked_action?" do
      twirp_item = TwirpItemMock.new(action: Conduit::TwirpHelper.forked_action)
      feed_item = Conduit::FeedItem.new(twirp_item, actor: nil, subject: nil)

      assert_predicate feed_item, :forked_action?
    end

    test "#sponsored_action?" do
      twirp_item = TwirpItemMock.new(action: Conduit::TwirpHelper.sponsored_action)
      feed_item = Conduit::FeedItem.new(twirp_item, actor: nil, subject: nil)

      assert_predicate feed_item, :sponsored_action?
    end

    test "#recommended_action?" do
      twirp_item = TwirpItemMock.new(action: Conduit::TwirpHelper.recommended_action)
      feed_item = Conduit::FeedItem.new(twirp_item, actor: nil, subject: nil)

      assert_predicate feed_item, :recommended_action?
    end

    test "#near_sponsors_goal_action?" do
      twirp_item = TwirpItemMock.new(action: Conduit::TwirpHelper.near_sponsors_goal_action)
      feed_item = Conduit::FeedItem.new(twirp_item, actor: nil, subject: nil)

      assert_predicate feed_item, :near_sponsors_goal_action?
    end

    test "#key_for_item" do
      twirp_item = TwirpItemMock.new(action: TwirpHelper.created_action, subject_type: "repository")

      assert_equal "ACTION_CREATED_repository", Conduit::TwirpHelper.key_for_item(twirp_item)
    end

    test "a key method exists for each FeedItem::ITEM_TYPE" do
      existing_keys = Conduit::TwirpHelper.methods.grep(/_key\Z/).map { |m| Conduit::TwirpHelper.send(m) }
      expected_keys = Conduit::FeedItem::ITEM_TYPES.keys

      # This key is a temporary placeholder, remove in https://github.com/github/feeds/issues/655
      existing_keys.delete("temp_merged_pull_request_key")
      expected_keys.delete("temp_merged_pull_request_key")

      assert_equal existing_keys.sort, expected_keys.sort
    end
  end
end
