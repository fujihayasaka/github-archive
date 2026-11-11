# typed: false
# frozen_string_literal: true

module Stratocaster
  class Attributes::IssueComment < Attributes
    EVENT_TYPE = "IssueCommentEvent".freeze

    # Initializes the attributes for this event.
    #
    # comment_id - Integer ID of an Issue Comment
    #
    # Returns nothing.
    def from(comment_id)
      @comment = ::IssueComment.find_by_id(comment_id)
    end

    # Converts a saved Event into the args necessary to get the other
    # attributes for this event type.
    #
    # event - A saved Stratocaster::Event instance.
    #
    # Returns nothing
    def from_event(event)
      from(event.comment_id)
    end

    # Builds the Stratocaster::Event attribute hash.
    #
    # Returns a Hash of attributes for Stratocaster::Event#dispatch.
    def to_hash
      return {} unless @comment
      {
        event_type: EVENT_TYPE,
        repo: @comment.repository,
        sender: @comment.user,
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
      return [] unless @comment && @comment.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      targets_for @comment.issue
    end

    # Builds the event's payload.
    #
    # Returns a Hash.
    def payload
      return unless issue = @comment.try(:issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      {
        action: :created,
        issue: Api::Serializer.serialize(:issue_hash, issue),
        comment: Api::Serializer.serialize(:issue_comment_hash, @comment),
        legacy: { issue_id: @comment.issue_id, comment_id: @comment.id },
      }
    end

    # Builds the event's unique URL. This will be without the host url
    # because staff/enterprise environments can have different domains, and the
    # event data will be cached.
    #
    # Returns a String URL.
    def url
      if @comment.try(:issue).try(:repository) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        @comment.permalink(include_host: false)
      else
        "/"
      end
    end
  end
end
