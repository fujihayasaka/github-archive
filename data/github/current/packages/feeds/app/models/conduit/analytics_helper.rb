# typed: false
# frozen_string_literal: true

module Conduit
  module AnalyticsHelper
    module ResourceType
      REPOSITORY = "REPO"
      USER = "USER"
      PULL_REQUEST = "PULL_REQUEST"
      FEED_POST = "FEED_POST"
      TOPIC = "TOPIC"
      ISSUE = "ISSUE"
      PULL_REQUEST_COMMENT = "PULL_REQUEST_COMMENT"
      ISSUE_COMMENT = "ISSUE_COMMENT"
      PUSH_EVENT = "PUSH_EVENT"
    end

    module CardType
      ADDED_TO_LIST = "ADDED_TO_LIST"
      CREATED_DISCUSSION = "NEW_DISCUSSION"
      CREATED_FEED_POST = "CREATED_FEED_POST"
      CREATED_REPOSITORY = "CREATED_REPOSITORY"
      FOLLOW_RECOMMENDATION = "FOLLOW_RECOMMENDATION"
      FOLLOWED_USER = "FOLLOW"
      FORKED_REPOSITORY = "FORKED_REPOSITORY"
      MERGED_PULL_REQUEST = "MERGED_PULL_REQUEST"
      NEAR_SPONSORS_GOAL = "NEAR_SPONSORS_GOAL"
      PUBLISHED_RELEASE = "RELEASE"
      PRIVATE_TO_PUBLIC_REPOSITORY = "PRIVATE_TO_PUBLIC_REPOSITORY"
      REPOSITORY_RECOMMENDATION = "REPOSITORY_RECOMMENDATION"
      SPONSORABLE_USER = "NEWLY_SPONSORABLE"
      SPONSORED_USER = "SPONSORSHIP"
      STARRED_REPOSITORY = "STARRED_REPOSITORY"
      TRENDING_REPOSITORY = "TRENDING_REPOSITORY"
      LABELED_ISSUE = "LABELED_ISSUE"
      LABELED_PULL_REQUEST = "LABELED_PULL_REQUEST"
      CLOSED_PULL_REQUEST = "CLOSED_PULL_REQUEST"
      ISSUE_CREATED = "ISSUE_CREATED"
      CREATED_PULL_REQUEST = "CREATED_PULL_REQUEST"
      ISSUE_CLOSED = "ISSUE_CLOSED"
      ISSUE_REOPENED = "ISSUE_REOPENED"
      REOPENED_PULL_REQUEST = "REOPENED_PULL_REQUEST"
      MEMBER_ADD_TO_REPO = "MEMBER_ADD_TO_REPO"
      PULL_REQUEST_COMMENTED = "PULL_REQUEST_COMMENTED"
      ISSUE_COMMENTED = "ISSUE_COMMENTED"
      PUSH = "PUSH"
    end

    module InteractionMethod
      INTERACTION_METHOD_CREATE = "INTERACTION_METHOD_CREATE"
      INTERACTION_METHOD_DELETE = "INTERACTION_METHOD_DELETE"
      INTERACTION_METHOD_UPDATE = "INTERACTION_METHOD_UPDATE"
      INTERACTION_METHOD_CANCEL = "INTERACTION_METHOD_CANCEL"
    end

    def analytics_attributes
      {
        card_type:             analytics_card_type,
        resource_relationship: relationship,
        created_at:            created_at,
        record_id:             subject_id,
        resource_type:         resource_type,
        resource_id:           resource_id,
        card_position:         idx,
        card_sub_position:     sub_idx,
        card_retrieved_id:     card_retrieved_id,
        ranking_model_id:      ranking_model_id || "",
        gatherer:              gatherer,
        variant:               (variants || {}).to_json,
        assignment_context:    assignment_context || "",
      }
    end

    # Public: Get the Hydro `card_type` for this feed item. Required for our analytics events.
    #
    # See https://github.com/github/hydro-schemas/blob/374bbaf482d6819c4086b69173d0b19025c28200/proto/hydro/schemas/github/feeds/v0/entities/feed_card.proto#L11-L20 for valid values.
    #
    # Returns a String.
    def analytics_card_type
      raise NotImplementedError.new("Expected #{self.class.name} to implement #{__method__}")
    end

    def resource_type
      raise NotImplementedError.new("Expected #{self.class.name} to implement #{__method__}")
    end

    def resource_id
      raise NotImplementedError.new("Expected #{self.class.name} to implement #{__method__}")
    end

    private

    def relationship
      twirp_item.relationship
    end

    def card_retrieved_id
      twirp_item.card_retrieved_id
    end
  end
end
