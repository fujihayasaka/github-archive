# typed: true
# frozen_string_literal: true

require "test_helper"

class Conduit::FeedItemCollectionTest < GitHub::TestCase
  fixtures do
    @viewer = create(:user)
  end

  test "is chainable" do
    disable_feature_flag(:feed_posts)

    exclude_all_filter = Conduit::FeedFilter.new(
      Conduit::FeedFilter::exclude_all_filter,
      viewer: @viewer
    )
    group_filter = Conduit::FeedFilter.new(
      exclude_all_filter.with_groups(["Stars"]),
      viewer: @viewer
    )

    collection = Conduit::FeedItemCollection.new([
      build(:twirp_conduit_created_feed_post_feed_item),
      build(:twirp_conduit_added_to_list_feed_item),
      build(:twirp_conduit_repository_feed_item)
    ])

    items = collection
      .apply_filter(group_filter)
      .filter_feed_posts(viewer: @viewer)
      .shuffle_repo_recs

    assert_equal 1, items.size
  end

  context "#filter_feed_posts" do
    test "when feature is disabled" do
      disable_feature_flag(:feed_posts)

      collection = Conduit::FeedItemCollection.new([
        build(:twirp_conduit_created_feed_post_feed_item)
      ])

      items = collection
        .filter_feed_posts(viewer: @viewer)

      assert_empty items
    end

    test "when feature is enabled" do
      enable_feature_flag(:feed_posts)

      collection = Conduit::FeedItemCollection.new([
        build(:twirp_conduit_created_feed_post_feed_item)
      ])

      items = collection
        .filter_feed_posts(viewer: @viewer)

      assert_equal 1, items.size
    end
  end

  context "#filter_trending_repos" do
    context "when nux_explore_repos is disabled", skip_if_feature_enabled: :nux_explore_repos do
      test "does not exclude trending repos" do
        collection = Conduit::FeedItemCollection.new([
          build(:twirp_conduit_trending_repository_feed_item)
        ])

        items = collection.filter_trending_repos(viewer: @viewer)

        assert_equal 1, items.size
      end
    end

    context "when nux_explore_repos is enabled", skip_if_feature_disabled: :nux_explore_repos do
      test "does not exclude trending repos when viewer joined over a month ago" do
        viewer = create(:user, created_at: 2.months.ago)
        collection = Conduit::FeedItemCollection.new([
          build(:twirp_conduit_trending_repository_feed_item)
        ])

        items = collection.filter_trending_repos(viewer: viewer)

        assert_equal 1, items.size
      end

      test "excludes trending repos when viewer joined in the last month" do
        collection = Conduit::FeedItemCollection.new([
          build(:twirp_conduit_trending_repository_feed_item)
        ])

        items = collection.filter_trending_repos(viewer: @viewer)

        assert_empty items
      end
    end
  end

  context "#apply_filter" do
    test "when filter is nil" do
      collection = Conduit::FeedItemCollection.new([
        build(:twirp_conduit_added_to_list_feed_item),
        build(:twirp_conduit_repository_feed_item)
      ])

      items = collection
        .apply_filter(nil)

      assert_equal 2, items.size
    end

    test "when filter is not nil" do
      exclude_all_filter = Conduit::FeedFilter.new(
        Conduit::FeedFilter::exclude_all_filter,
        viewer: @viewer
      )
      group_filter = Conduit::FeedFilter.new(
        exclude_all_filter.with_groups(["Stars"]),
        viewer: @viewer
      )

      collection = Conduit::FeedItemCollection.new([
        build(:twirp_conduit_added_to_list_feed_item),
        build(:twirp_conduit_repository_feed_item)
      ])

      items = collection
        .apply_filter(group_filter)

      assert_equal 1, items.size
      assert_equal :SUBJECT_TYPE_USER_LIST_ITEM, items.first.subject_type
    end
  end

  context "#shuffle_repo_recs" do
    test "shuffles repo recs" do
      items = build_list(:twirp_conduit_repo_rec_feed_item, 50)

      collection = Conduit::FeedItemCollection.new(items)
      first_pass = collection.shuffle_repo_recs.dup
      second_pass = collection.shuffle_repo_recs.dup

      assert_same_elements first_pass, second_pass
      refute_equal first_pass, second_pass
    end

    test "does not shuffle other feed items" do
      twirp_items = [
        build(:twirp_conduit_user_feed_item),
        build(:twirp_conduit_repo_rec_feed_item),
        build(:twirp_conduit_discussion_feed_item),
        build(:twirp_conduit_repo_rec_feed_item),
      ]
      collection = Conduit::FeedItemCollection.new(twirp_items)

      items = collection
        .shuffle_repo_recs

      assert_equal twirp_items[0], items[0]
      assert_equal twirp_items[2], items[2]
    end
  end

  context "#filter_off_topic_repos" do
    test "with off topic repos" do
      repo = create(:repository)
      topic = create(:topic)
      create(:repository_topic, topic: topic, repository: repo)

      topic_item = build(:twirp_conduit_repository_feed_item, repository: repo)
      user_item = build(:twirp_conduit_user_feed_item)
      off_topic_item = build(:twirp_conduit_repository_feed_item)
      twirp_items = [topic_item, user_item, off_topic_item]

      collection = Conduit::FeedItemCollection.new(twirp_items)
      items = collection.filter_off_topic_repos(topic)

      assert_includes items, topic_item
      assert_includes items, user_item
      refute_includes items, off_topic_item
    end

    test "with on-topic related items" do
      repo = create(:repository)
      topic = create(:topic)
      create(:repository_topic, topic: topic, repository: repo)

      topic_item = build(:twirp_conduit_repository_feed_item, repository: repo, related_items: [
        build(:twirp_conduit_repository_feed_item, repository: repo),
      ])
      user_item = build(:twirp_conduit_user_feed_item)
      off_topic_item = build(:twirp_conduit_repository_feed_item)
      twirp_items = [topic_item, user_item, off_topic_item]

      collection = Conduit::FeedItemCollection.new(twirp_items)
      items = collection.filter_off_topic_repos(topic)

      assert_includes items, topic_item
      refute_empty topic_item.related_items
      assert_includes items, user_item
      refute_includes items, off_topic_item
    end

    test "with off-topic related items" do
      repo = create(:repository)
      topic = create(:topic)
      create(:repository_topic, topic: topic, repository: repo)

      topic_item = build(:twirp_conduit_repository_feed_item, repository: repo, related_items: [
        build(:twirp_conduit_repository_feed_item)
      ])
      user_item = build(:twirp_conduit_user_feed_item)
      off_topic_item = build(:twirp_conduit_repository_feed_item)
      twirp_items = [topic_item, user_item, off_topic_item]

      collection = Conduit::FeedItemCollection.new(twirp_items)
      items = collection.filter_off_topic_repos(topic)

      assert_includes items, topic_item
      assert_empty topic_item.related_items
      assert_includes items, user_item
      refute_includes items, off_topic_item
    end
  end
end
