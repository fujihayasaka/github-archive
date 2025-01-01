# typed: false
# frozen_string_literal: true

module Stratocaster
  class Attributes::CommitComment < Attributes
    EVENT_TYPE = "CommitCommentEvent".freeze

    # Initializes the attributes for this event.
    #
    # comment_id - Integer ID of a Commit Comment
    #
    # Returns nothing.
    def from(comment_id)
      @comment = ::CommitComment.find_by_id(comment_id)
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
        created_at: @comment.created_at&.to_i,
      }
    end

    # Builds the list of targets for an event.
    #
    # timeline_type - an optional String for the timeline that will be shown
    #
    # Returns an Array of User IDs.
    def targets(timeline_type = nil)
      return [] if @comment.blank? || @comment.repository.blank?
      targets_for @comment.repository
    end

    # Builds the event's payload.
    #
    # Returns a Hash.
    def payload
      {
        comment: Api::Serializer.serialize(:commit_comment_hash, @comment),
        legacy: { commit: @comment.commit_id, comment_id: @comment.id },
      }
    end

    # Builds the event's unique URL. This will be without the host url
    # because staff/enterprise environments can have different domains, and the
    # event data will be cached.
    #
    # Returns a String URL.
    def url
      return "/" unless @comment.try(:repository)
      @comment.full_permalink(include_host: false)
    end
  end
end
