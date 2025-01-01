# typed: false
# frozen_string_literal: true

module Stratocaster
  class Attributes::Follow < Attributes
    EVENT_TYPE = "FollowEvent".freeze

    # Initializes the attributes for this event.
    #
    # target_id - The ID of the User being followed.
    # actor_id  - The ID of the User following the target.
    #
    # Returns nothing.
    def from(target_id, actor_id)
      return unless @target = User.find_by_id(target_id)
      @actor = User.find_by_id(actor_id)
    end

    # Converts a saved Event into the args necessary to get the other
    # attributes for this event type.
    #
    # event - A saved Stratocaster::Event instance.
    #
    # Returns nothing
    def from_event(event)
      @target = User.find_by_id(event.target_id)
      @actor = event.sender_record
    end

    # Builds the Stratocaster::Event attribute hash.
    #
    # Returns a Hash of attributes for Stratocaster::Event#dispatch.
    def to_hash
      return {} unless @target && @actor
      {
        event_type: EVENT_TYPE,
        sender: @actor,
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
      targets_for @actor, @target.id
    end

    # Builds the event's payload.
    #
    # Returns a Hash.
    def payload
      {
        target: Api::Serializer.serialize(:user_hash, @target, full: true),
        legacy: { target: {
            id: @target.id,
            login: @target.to_s,
            followers: @target.followeds.count,
            repos: @target.public_repositories.size,
            gravatar_id: "",
          } },
      }
    end

    # Builds the event's unique URL.
    #
    # Returns a String URL.
    def url
      "/#{@target}"
    end
  end
end
