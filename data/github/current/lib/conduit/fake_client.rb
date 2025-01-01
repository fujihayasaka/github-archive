# typed: true
# frozen_string_literal: true

require "monolith-twirp-conduit-feeds"

module Conduit
  class FakeClient
    def get_for_you_feed(user:, variants:, disable_cache: false, include_starred_relationships_filter: true, repository_subscriptions: [])
      discussion = MonolithTwirp::Conduit::Feeds::V1::Discussion.new(
        id: 987234,
        title: "A title",
        author: MonolithTwirp::Conduit::Feeds::V1::User.new(
          id: 345,
          login: "monalisa",
          type: "TYPE_USER",
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
          type: "TYPE_USER",
        ),
        action: "ACTION_CREATED",
        time: Time.now,
        subject_type: "SUBJECT_TYPE_DISCUSSION",
        relationship: "self",
        gatherer: "second_degree",
        card_retrieved_id: "abc123",
        related_items: [],
        related_by: "RELATED_BY_NONE",
        event_id: 345,
        event_type: "discussion_create",
        discussion_subject: discussion,
      )
      {
        items: ::Conduit::FeedItemCollection.new([item]),
        ranking_model_id: "abc123"
      }
    end
  end
end
