# typed: false
# frozen_string_literal: true

module Stratocaster
  class Attributes::PullRequestReview < Attributes
    EVENT_TYPE = "PullRequestReviewEvent".freeze

    # Initializes the attributes for this event.
    #
    # review_id - Integer ID of a Review
    #
    # Returns nothing.
    def from(review_id)
      @review = ::PullRequestReview.find_by_id(review_id)
    end

    # Converts a saved Event into the args necessary to get the other
    # attributes for this event type.
    #
    # event - A saved Stratocaster::Event instance.
    #
    # Returns nothing
    def from_event(event)
      from(event.review_id)
    end

    # Builds the Stratocaster::Event attribute hash.
    #
    # Returns a Hash of attributes for Stratocaster::Event#dispatch.
    def to_hash
      return {} unless @review
      {
        event_type: EVENT_TYPE,
        repo: @review.repository,
        sender: @review.user,
        url: url,
        payload: payload,
      }
    end

    # Builds the list of targets for an event.
    #
    # timeline_type - an optional String for the timeline that will be shown
    #
    # Returns an Array of User IDs.
    def targets(timeline_type = nil)
      return [] unless @review && @review.repository
      targets_for @review.repository
    end

    # Builds the event's payload.
    #
    # Returns a Hash.
    def payload
      {
        action: :created,
        review: Api::Serializer.serialize(:pull_request_review_hash, @review),
        pull_request: Api::Serializer.serialize(:pull_request_hash, @review.pull_request)
      }
    end

    # Builds the event's unique URL. This will be without the host url
    # because staff/enterprise environments can have different domains, and the
    # event data will be cached.
    #
    # Returns a String URL.
    def url
      if @review.try(:pull_request).try(:repository)
        @review.permalink(include_host: false)
      else
        "/"
      end
    end
  end
end
