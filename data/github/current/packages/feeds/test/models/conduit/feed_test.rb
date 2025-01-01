# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

class Conduit::FeedTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @user = create(:user)
  end

  test "Filters items that do not satisfy the ip_allowlist CAP policy", skip_enterprise: true do
    GitHub.flipper[:filter_conduit_cap_policy].enable

    org = create(:enterprise_linked_organization, login: "bookish-potato")
    org.enable_ip_allowlist actor: org.owner
    repo = create(:repository, owner: org)
    org.add_member(@user)
    create(:ip_allowlist_entry, :org, allow_list_value: "1.1.1.1", owner: org.owner)

    twirp_item = build(:twirp_conduit_repository_feed_item, repository: repo)
    filter = cap_authorizing_filter([repo])
    feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user, cap_filter: filter)
    assert_empty feed.items
  end

  test "Does not filters items that do satisfy the ip_allowlist CAP policy", skip_enterprise: true do
    GitHub.flipper[:filter_conduit_cap_policy].enable

    org = create(:enterprise_linked_organization, login: "bookish-potato")
    org.enable_ip_allowlist actor: org.owner
    repo = create(:repository, owner: org)
    org.add_member(@user)
    create(:ip_allowlist_entry, :org, allow_list_value: "1.1.1.1", owner: org.owner)

    twirp_item = build(:twirp_conduit_repository_feed_item, repository: repo)
    filter = cap_unauthorizing_filter([repo])
    feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user, cap_filter: filter)
    assert_equal 1, feed.items.size
  end

  test "Does not load user list items unless the user list exists" do
    twirp_items = build(:twirp_conduit_added_to_list_feed_item)
    Conduit::Feed.any_instance.stubs(:user_lists_by_id).returns({})
    feed = build(:conduit_feed, twirp_items: [twirp_items])

    assert_empty feed.items
  end

  test "Does not load user list items unless the repository exists" do
    twirp_item = build(:twirp_conduit_added_to_list_feed_item)
    Conduit::Feed.any_instance.stubs(:repositories_by_id).returns({})
    feed = build(:conduit_feed, twirp_items: [twirp_item])

    assert_empty feed.items
  end

  test "Does not show user events when the user is ghost" do
    ghost = User.create_ghost
    twirp_items = build(:twirp_conduit_user_feed_item, subject_user: ghost)
    feed = build(:conduit_feed, twirp_items: [twirp_items])

    assert_empty feed.items
  end

  test "announcements discussions with an empty body are excluded" do
    repo = create(:repository, has_discussions: true, owner: create(:verified_user))
    category = repo.discussion_categories.find_by(supports_announcements: true)
    discussion = create(
      :discussion,
      state: :converting,
      issue: create(:issue),
      repository: repo,
      user: repo.owner,
      actor: repo.owner,
      category: category,
    )
    twirp_item = build(:twirp_conduit_discussion_feed_item, discussion: discussion)
    discussion.update!(body: nil) # doing this to bypass twirp/protobuf validation

    feed = build(:conduit_feed, twirp_items: [twirp_item])

    assert_empty feed.items
  end

  context "#empty?" do
    test "true" do
      feed = build(:conduit_feed)
      assert_predicate feed, :empty?
    end

    test "false" do
      twirp_item = build(:twirp_conduit_added_to_list_feed_item)
      feed = build(:conduit_feed, twirp_items: [twirp_item])

      refute_predicate feed, :empty?
    end
  end

  context "#filtered?" do
    test "true" do
      filter_values = Conduit::FeedFilter::exclude_all_filter
      filter = Conduit::FeedFilter.new(filter_values, viewer: @user)
      feed = build(:conduit_feed, filter: filter, user: @user)

      assert_predicate feed, :filtered?
    end

    test "false" do
      filter_values = Conduit::FeedFilter.include_all_filter
      filter = Conduit::FeedFilter.new(filter_values, viewer: @user)
      feed = build(:conduit_feed, user: @user, filter: filter)

      refute_predicate feed, :filtered?
    end

    test "false without a filter" do
      feed = build(:conduit_feed)

      refute_predicate feed, :filtered?
    end
  end

  context "card position and sub-position" do
    test "card position for non-rollup non-related items is the index of the item" do
      twirp_items = build_list(:twirp_conduit_added_to_list_feed_item, 2)
      feed = build(:conduit_feed, twirp_items: twirp_items)

      assert_equal 0, feed.items[0].idx
      assert_equal 1, feed.items[1].idx
    end

    test "card sub-position for non-rollup non-related items is nil" do
      twirp_items = build_list(:twirp_conduit_added_to_list_feed_item, 2)

      feed = build(:conduit_feed, twirp_items: twirp_items)

      assert_nil feed.items[0].sub_idx
      assert_nil feed.items[1].sub_idx
    end

    test "rollup card position and sub-position are set correctly" do
      actor = create(:user)
      followee = create(:user)
      related_followee = create(:user)
      rollup_twirp_item = build(:twirp_conduit_user_feed_item,
        subject_user: followee,
        actor_user: actor,
        action: ::Conduit::TwirpHelper.followed_action,
        related_items: [
          build(:twirp_conduit_user_feed_item,
            subject_user: related_followee,
            actor_user: actor,
            action: ::Conduit::TwirpHelper.followed_action,
          ),
        ],
      )

      feed = build(:conduit_feed, twirp_items: [rollup_twirp_item])
      rollup_parent_item = feed.items.first
      rollup_related_item = rollup_parent_item.related_items.first

      assert_equal rollup_parent_item.idx, rollup_related_item.idx, "related items should share the same idx as the parent item"
      assert_equal 0, rollup_parent_item.sub_idx, "first item in rollup should have a sub_idx of 0"
      assert_equal 1, rollup_related_item.sub_idx, "second item in rollup should have sub_idx of 1"
    end
  end

  context "pagination" do
    test "loads PER_PAGE events" do
      Conduit::Feed.stub_const(:PER_PAGE, 2) do
        twirp_items = build_list(:twirp_conduit_user_feed_item, 4)
        actor_ids = twirp_items.map { |i| i.actor.id }
        feed = build(:conduit_feed, twirp_items: twirp_items)

        assert_equal 2, feed.items.count
        assert_equal actor_ids.first(2), feed.items.map(&:actor_id)
      end
    end

    test "loads all events with ignore_pagination is true" do
      Conduit::Feed.stub_const(:PER_PAGE, 2) do
        twirp_items = build_list(:twirp_conduit_user_feed_item, 4)
        actor_ids = twirp_items.map { |i| i.actor.id }
        feed = build(:conduit_feed, twirp_items: twirp_items, ignore_pagination: true)

        assert_equal 4, feed.items.count
        assert_equal actor_ids, feed.items.map(&:actor_id)
      end
    end
  end
end
