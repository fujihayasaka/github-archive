# typed: true
# frozen_string_literal: true

require "monolith-twirp-conduit-feeds"

module Conduit
  class FakeClient < Client
    def get_for_you_feed(user:, variants:, disable_cache: false, include_starred_relationships: true, repository_subscriptions: [], event_types: [])
      discussion = MonolithTwirp::Conduit::Feeds::V1::Discussion.new(
        id: 987234,
        title: "A title",
        author: MonolithTwirp::Conduit::Feeds::V1::User.new(
          id: 345,
          login: "monalisa",
          type: :TYPE_USER,
        ),
        repository: MonolithTwirp::Conduit::Feeds::V1::Repository.new(
          id: 234,
        ),
        comment_count: 3,
        total_upvotes: 5,
        body_html: "hello, world",
      )
      item = MonolithTwirp::Conduit::Feeds::V1::FeedItem.new(
        actor: MonolithTwirp::Conduit::Feeds::V1::User.new(
          id: 123,
          login: "monalisa",
          type: :TYPE_USER,
        ),
        action: :ACTION_CREATED,
        time: Time.now.to_proto,
        subject_type: :SUBJECT_TYPE_DISCUSSION,
        relationship: "self",
        gatherer: "second_degree",
        card_retrieved_id: "abc123",
        related_items: [],
        related_by: :RELATED_BY_NONE,
        event_id: 345,
        event_type: "discussion_create",
        discussion_subject: discussion,
      )
      {
        items: ::Conduit::FeedItemCollection.new([item]),
        ranking_model_id: "abc123"
      }
    end

    def get_repository_events(viewer:, repository_ids:, issues_only: false)
      discussion = MonolithTwirp::Conduit::Feeds::V1::Discussion.new(
        id: 987234,
        title: "A title",
        author: MonolithTwirp::Conduit::Feeds::V1::User.new(
          id: 345,
          login: "monalisa",
          type: :TYPE_USER,
        ),
        repository: MonolithTwirp::Conduit::Feeds::V1::Repository.new(
          id: repository_ids.first,
        ),
        comment_count: 3,
        total_upvotes: 5,
        body_html: "hello, world",
      )
      item = MonolithTwirp::Conduit::Feeds::V1::FeedItem.new(
        actor: MonolithTwirp::Conduit::Feeds::V1::User.new(
          id: 123,
          login: "monalisa",
          type: :TYPE_USER,
        ),
        action: :ACTION_CREATED,
        time: Time.now.to_proto,
        subject_type: :SUBJECT_TYPE_DISCUSSION,
        relationship: "self",
        gatherer: "second_degree",
        card_retrieved_id: "abc123",
        related_items: [],
        related_by: :RELATED_BY_NONE,
        event_id: 345,
        event_type: "discussion_create",
        discussion_subject: discussion,
      )
      {
        items: ::Conduit::FeedItemCollection.new([item]),
      }
    end

    def get_user_events(viewer:, user:, public_only: false)
      discussion = MonolithTwirp::Conduit::Feeds::V1::Discussion.new(
        id: 987234,
        title: "A title",
        author: MonolithTwirp::Conduit::Feeds::V1::User.new(
          id: 345,
          login: "monalisa",
          type: :TYPE_USER,
        ),
        comment_count: 3,
        total_upvotes: 5,
        body_html: "hello, world",
      )
      item = MonolithTwirp::Conduit::Feeds::V1::FeedItem.new(
        actor: MonolithTwirp::Conduit::Feeds::V1::User.new(
          id: 123,
          login: "monalisa",
          type: :TYPE_USER,
        ),
        action: :ACTION_CREATED,
        time: (Time.now - 13.months).to_proto, # makes this a dormant user
        subject_type: :SUBJECT_TYPE_DISCUSSION,
        relationship: "self",
        gatherer: "second_degree",
        card_retrieved_id: "abc123",
        related_items: [],
        related_by: :RELATED_BY_NONE,
        event_id: 345,
        event_type: "discussion_create",
        discussion_subject: discussion,
      )
      {
        items: ::Conduit::FeedItemCollection.new([item]),
      }
    end
  end
end
