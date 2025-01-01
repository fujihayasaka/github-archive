# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::CreatedDiscussion < FeedItem
    delegate :repository, to: :discussion

    GRAPHQL_TYPE = Platform::Objects::Conduit::CreatedDiscussionFeedItem
    UNIVERSE_DISCUSSION_ID = 4464444

    def discussion
      subject
    end

    # Display
    def action_string
      if rollup?
        count = related_items.size + 1
        "#{count} new #{"discussion".pluralize(count)}"
      else
        "a discussion in"
      end
    end

    def description
      "#{actor.display_login} created a new discussion in #{discussion.category.name}"
    end

    # Analytics
    def analytics_card_type
      CardType::CREATED_DISCUSSION
    end

    def resource_type
      ResourceType::REPOSITORY
    end

    def resource_id
      repository.id
    end

    def source
      repository.name_with_display_owner
    end

    def detected_language_english?
      return true if discussion.detected_language.nil?
      discussion.detected_language == "en"
    end

    def rollup?
      return false unless super
      related_items.each do |ri|
        return false unless ri.detected_language_english?
      end
      true
    end

    def async_preview_image_url(viewer:)
      # Update this to prioritize a custom preview image
      repository.async_open_graph_image_url(viewer: viewer)
    end

    # TODO: Remove this once the UI is built out for multiple announcements in mobile
    def universe_announcement?
      subject.id == UNIVERSE_DISCUSSION_ID
    end

    # Override Conduit::FeedItem#reason_message
    #
    # The superclass implementation assumes that a follow relationship is between
    # the viewer and the item.actor, but for discussion events a follow relationship
    # means the viewer is following the repository owner (user follows org).
    memoize def reason_message
      return unless repository
      return unless viewer

      relationship = reason&.split(",").first&.downcase&.to_sym

      @reason_message =
      if ACTOR_REASON.key?(relationship) && repository&.owner&.present?
        ACTOR_REASON[relationship] % [repository.owner.display_login]
      elsif SUBJECT_REASON.key?(relationship) && repository.present?
        SUBJECT_REASON[relationship] % [repository.name_with_display_owner]
      else
        nil
      end
    end

    def api_type
      "DiscussionEvent"
    end

    def payload
      {
        action: :created,
        discussion: ::Api::Serializer.serialize(:discussion_hash, discussion)
      }
    end
  end
end
