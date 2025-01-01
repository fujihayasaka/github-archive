# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItemTest < GitHub::TestCase
    include FeedTestHelpers

    fixtures do
      @actor = create(:user)
      @subject = create(:user)
      @repo = create(:repository)
    end

    setup do
      @twirp_item = build(:twirp_conduit_user_feed_item, actor_user: @actor, subject_user: @subject)
      @feed_item = Conduit::FeedItem.new(@twirp_item, actor: @actor, subject: @subject)
    end

    test "builds a feed item" do
      feed_item = build(:repository_feed_item)
      assert_equal feed_item.class, Conduit::FeedItem::StarredRepository
    end

    test "builds related feed items" do
      item = build(:twirp_conduit_user_feed_item)
      related_item = build(:twirp_conduit_user_feed_item)

      # using `+=` intentionally so that the array is converted to
      # a native protobuf array. regular assignment doesn't work
      # see: https://developers.google.com/protocol-buffers/docs/reference/ruby-generated#repeated-fields
      item.related_items += [related_item]

      feed = build(:conduit_feed, twirp_items: [item])
      feed_item = feed.items.first

      assert_equal feed_item.class, Conduit::FeedItem::FollowedUser
      assert_equal feed_item.related_items.size, 1
      assert_equal 0, feed_item.sub_idx

      related_feed_item = feed_item.related_items.first
      assert_equal feed_item.idx, related_feed_item.idx
      assert_equal 1, related_feed_item.sub_idx
      assert_equal related_feed_item.class, Conduit::FeedItem::FollowedUser
    end

    test "#actor_id returns actor ID" do
      assert_equal @actor.id, @feed_item.actor_id
    end

    test "#subject_id returns subject ID" do
      assert_equal @subject.id, @feed_item.subject_id
    end

    test "#item_key returns item action + subject_type" do
      assert_equal "#{@twirp_item.action}_#{@twirp_item.subject_type}", @feed_item.item_key
    end

    test "#actor_relationship returns actor relationship to subject" do
      twirp_item = build(:twirp_conduit_user_feed_item)

      twirp_item.relationship = "sponsored,followed"
      feed_item = Conduit::FeedItem.new(twirp_item, actor: @actor, subject: @subject)
      relationships = feed_item.reason&.split(",").map(&:downcase)

      assert_equal :followed, feed_item.actor_relationship(relationships)
    end
  end

  class FeedItemIdentityTest < GitHub::TestCase
    test "#user_event? returns true for followed user and sponsored user events" do
      [
        {
          action: Conduit::TwirpHelper.followed_action,
          class: Conduit::FeedItem::FollowedUser
        },
        {
          action: Conduit::TwirpHelper.sponsored_action,
          class: Conduit::FeedItem::SponsoredUser
        }
      ].each do |event|
        feed_item = build(:user_feed_item, action: event[:action])

        assert_equal event[:class], feed_item.class
        assert_equal true, feed_item.user_event?
      end
    end

    test "#discussion_event? returns true for created_discussion events" do
      feed_item = build(:discussion_feed_item)
      assert_equal Conduit::FeedItem::CreatedDiscussion, feed_item.class
      assert_equal true, feed_item.discussion_event?
    end

    test "#release_event? returns true for published release events" do
      feed_item = build(:release_feed_item)
      assert_equal Conduit::FeedItem::PublishedRelease, feed_item.class
      assert_equal true, feed_item.release_event?
    end

    test "#repo_event? returns true for created repository, forked repository, starred repository, and repository recommendation events", skip_if_feature_enabled: :turn_off_jazz_user_repository_recommendations do
      [
        {
          action: Conduit::TwirpHelper.created_action,
          class: Conduit::FeedItem::CreatedRepository
        },
        {
          action: Conduit::TwirpHelper.forked_action,
          class: Conduit::FeedItem::ForkedRepository
        },
        {
          action: Conduit::TwirpHelper.starred_action,
          class: Conduit::FeedItem::StarredRepository
        },
        {
          action: Conduit::TwirpHelper.recommended_action,
          class: Conduit::FeedItem::RepositoryRecommendation
        }
      ].each do |event|
        feed_item = build(:repository_feed_item, action: event[:action])
        assert_equal event[:class], feed_item.class
        assert_equal true, feed_item.repo_event?
      end
    end

    test "#repo_event? returns true added to list events" do
      feed_item = build(:user_list_feed_item)

      assert_equal Conduit::FeedItem::AddedToList, feed_item.class
      assert_equal true, feed_item.repo_event?
    end

    test "#push_event? returns true for push events" do
      feed_item = build(:push_event_item)

      assert_equal Conduit::FeedItem::PushEvent, feed_item.class
      assert_equal true, feed_item.push_event?
    end

    context "#target_for_conditional_access" do
      test "returns the subject's target for a non-push event" do
        user = create(:user)
        feed_item = build(:user_feed_item, subject: user)

        assert_equal feed_item.target_for_conditional_access, user.target_for_conditional_access
      end

      test "returns the repository target for a push event" do
        repository = create(:repository, from_example: :simple)
        push = create(:push, repository: repository)
        feed_item = build(:push_event_item, subject: push)

        assert_equal feed_item.target_for_conditional_access, repository.target_for_conditional_access
      end
    end
  end

  class FeedItemGraphQLTest < GitHub::TestCase
    # There's a contract between a Conduit::FeedItem and its respective
    # GraphQL class. To properly support GraphQL clients we've chosen to
    # provid a :description method which is to be used as a fallback
    # when the client doesn't yet support the card type
    test "has a description method" do
      Conduit::FeedItem::ITEM_TYPES.values.each do |type|
        refute_empty type.instance_methods.grep(:description)
      end
    end

    test "has a corresponding graphql type" do
      types = Conduit::FeedItem::ITEM_TYPES.values.select(&:supports_graphql?)
      expected_graphql_types = types.map { |type| type.const_get(:GRAPHQL_TYPE) }
      actual_graphql_types = Platform::Unions::FeedItem.possible_types

      assert_equal expected_graphql_types.size, actual_graphql_types.size
      assert_empty actual_graphql_types - expected_graphql_types
    end
  end

  class FeedItemInitializationTest < GitHub::TestCase
    fixtures do
      @actor = create(:user)
      @subject = create(:user)
    end

    setup do
      @feed_item = build(:user_feed_item, actor: @actor, subject: @subject)
    end

    test "does not build an unknown item type" do
      repository = create(:repository)
      twirp_item = build(
        :twirp_conduit_repository_feed_item,
        repository: repository,
        action: "ACTION_INVALID",
      )
      feed_item = ::Conduit::FeedItem.build(twirp_item, actor: repository.owner, subject: repository)

      assert_nil feed_item
    end

    test "does not build without an actor" do
      twirp_item = build(:twirp_conduit_user_feed_item)
      feed_item = Conduit::FeedItem.build(twirp_item, actor: nil, subject: create(:user))

      assert_nil feed_item
    end

    test "does build without an actor if recommendation", skip_if_feature_enabled: :turn_off_jazz_user_repository_recommendations do
      twirp_item = build(:twirp_conduit_repo_rec_feed_item)
      feed_item = ::Conduit::FeedItem.build(twirp_item, actor: nil, subject: create(:user))

      assert_equal feed_item.class, Conduit::FeedItem::RepositoryRecommendation
    end

    test "doesn't build recommendation feed item if turn_off_jazz_user_repository_recommendations is enabled" do
      enable_feature_flag(:turn_off_jazz_user_repository_recommendations)

      twirp_item = build(:twirp_conduit_repo_rec_feed_item)
      feed_item = ::Conduit::FeedItem.build(twirp_item, actor: @actor, subject: @subject)

      assert_nil feed_item
    end

    test "does not build without a subject" do
      twirp_item = build(:twirp_conduit_user_feed_item)
      feed_item = ::Conduit::FeedItem.build(twirp_item, actor: create(:user), subject: nil)

      assert_nil feed_item
    end

    test "#actor_id returns actor ID" do
      assert_equal @actor.id, @feed_item.actor_id
    end

    test "#subject_id returns subject ID" do
      assert_equal @subject.id, @feed_item.subject_id
    end

    test "#item_key returns item action + subject_type" do
      twirp_item = @feed_item.instance_variable_get(:@twirp_item)
      assert_equal "#{twirp_item.action}_#{twirp_item.subject_type}", @feed_item.item_key
    end

    context "#contains_viewer" do
      test "true if viewer is card subject" do
        twirp_item = build(
          :twirp_conduit_user_feed_item,
          actor_user: @actor,
          subject_user: @subject,
          action: Conduit::TwirpHelper.followed_action
        )

        feed_item = ::Conduit::FeedItem.build(twirp_item, actor: @actor, subject: @subject, viewer: @subject)
        assert_predicate feed_item, :contains_viewer?
      end

      test "true if viewer is subject of related item" do
        top_subject_user = create(:user)
        top_twirp_item = build(
          :twirp_conduit_user_feed_item,
          actor_user: @actor,
          subject_user: top_subject_user,
          action: Conduit::TwirpHelper.followed_action
        )
        related_twirp_item = build(
          :twirp_conduit_user_feed_item,
          actor_user: @actor,
          subject_user: @subject,
          action: Conduit::TwirpHelper.followed_action
        )

        related_feed_item = ::Conduit::FeedItem.build(related_twirp_item, actor: @actor, subject: @subject, viewer: @subject)
        top_feed_item = ::Conduit::FeedItem.build(top_twirp_item, actor: @actor, subject: top_subject_user, related_items: [related_feed_item], viewer: @subject)
        assert_predicate top_feed_item, :contains_viewer?
      end

      test "false if viewer is neither card subject or related item subject" do
        top_twirp_item = build(
          :twirp_conduit_user_feed_item,
          actor_user: @actor,
          subject_user: create(:user),
          action: Conduit::TwirpHelper.followed_action
        )
        related_twirp_item = build(
          :twirp_conduit_user_feed_item,
          actor_user: @actor,
          subject_user: create(:user),
          action: Conduit::TwirpHelper.followed_action
        )

        related_feed_item = ::Conduit::FeedItem.build(related_twirp_item, actor: @actor, subject: create(:user), viewer: @subject)
        top_feed_item = ::Conduit::FeedItem.build(top_twirp_item, actor: @actor, subject: create(:user), related_items: [related_feed_item], viewer: @subject)

        refute_predicate top_feed_item, :contains_viewer?
      end
    end

    context "#announcement?" do
      test "true when gatherer is 'announcements'" do
        enable_feature_flag(:feed_pinned_announcements)

        twirp_item = build(:twirp_conduit_discussion_feed_item, gatherer: "announcements")
        feed_item = build(:discussion_feed_item, twirp_item: twirp_item)

        assert_predicate feed_item, :announcement?
        assert_predicate feed_item, :dismissible?
      end

      test "false when gatherer is not 'announcements'" do
        enable_feature_flag(:feed_pinned_announcements)

        twirp_item = build(:twirp_conduit_discussion_feed_item, gatherer: "blah blah")
        feed_item = build(:discussion_feed_item, twirp_item: twirp_item)

        refute_predicate feed_item, :announcement?
        refute_predicate feed_item, :dismissible?
      end
    end

    context "#multiple_announcements?" do
      test "false when item is not in the announcements gatherer" do
        enable_feature_flag(:feed_pinned_announcements)
        enable_feature_flag(:multiple_pinned_announcements)

        twirp_item = build(:twirp_conduit_discussion_feed_item, gatherer: "blah blah")
        feed_item = build(:discussion_feed_item, twirp_item: twirp_item)

        refute_predicate feed_item, :multiple_announcements?
      end

      test "false when item is in the announcements gatherer but there are no other announcements" do
        enable_feature_flag(:feed_pinned_announcements)
        enable_feature_flag(:multiple_pinned_announcements)

        twirp_item = build(:twirp_conduit_discussion_feed_item, gatherer: "announcements")
        feed_item = build(:discussion_feed_item, twirp_item: twirp_item)

        refute_predicate feed_item, :multiple_announcements?
      end

      test "true when item is in the announcements gatherer and there are other announcements" do
        enable_feature_flag(:feed_pinned_announcements)
        enable_feature_flag(:multiple_pinned_announcements)

        twirp_item = build(:twirp_conduit_discussion_feed_item, gatherer: "announcements")
        related_twirp_item = build(:twirp_conduit_discussion_feed_item, gatherer: "announcements")
        related_feed_item = build(:discussion_feed_item, twirp_item: related_twirp_item, idx: 1, sub_idx: 1)
        feed_item = build(:discussion_feed_item, twirp_item: twirp_item, related_items: [related_feed_item])

        assert_predicate feed_item, :multiple_announcements?
        assert_predicate related_feed_item, :multiple_announcements?
      end
    end

    context "#issue_event?" do
      test "returns true for issue events" do
        assert build(:issue_feed_item, :assigned).issue_event?
        assert build(:issue_feed_item, :created).issue_event?
        assert build(:issue_feed_item, :closed).issue_event?
      end

      test "returns false for non-issue events" do
        refute build(:release_feed_item).issue_event?
        refute build(:discussion_feed_item).issue_event?
      end
    end

    context "#pull_request_event?" do
      test "returns true for PR events" do
        assert build(:pull_request_feed_item, :labeled).pull_request_event?
        assert build(:pull_request_feed_item, :created).pull_request_event?
        assert build(:pull_request_feed_item, :closed).pull_request_event?
      end

      test "returns false for non-PR events" do
        refute build(:release_feed_item).pull_request_event?
        refute build(:discussion_feed_item).pull_request_event?
      end
    end
  end
end
