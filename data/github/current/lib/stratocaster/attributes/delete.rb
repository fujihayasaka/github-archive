# typed: false
# frozen_string_literal: true

module Stratocaster
  class Attributes::Delete < Attributes
    EVENT_TYPE = "DeleteEvent".freeze

    # Initializes the attributes for this event.
    #
    # repo_id   - Integer Repository ID or a Repository
    # ref       - The String git ref that was deleted.  nil if just a
    #             Repository was deleted.
    # pusher_id - Optional ID of the User that pushed a ref, or nil.
    #
    # Returns nothing.
    def from(repo_id, ref = nil, pusher_id = nil)
      return unless @repo =
        repo_id.is_a?(Repository) ? repo_id : Repository.find_by_id(repo_id)
      @ref_type = RefType.from_ref(ref)
      @ref = parse_ref(ref)
      set_actor_from_pusher(pusher_id)
    end

    # Converts a saved Event into the args necessary to get the other
    # attributes for this event type.
    #
    # event - A saved Stratocaster::Event instance.
    #
    # Returns nothing
    def from_event(event)
      @actor    = event.sender_record
      @repo     = event.repo_record
      @ref_type = RefType.new(event.ref_type)
      @ref      = event.ref
      @pusher_type = event.pusher_type
    end

    # Builds the Stratocaster::Event attribute hash.
    #
    # Returns a Hash of attributes for Stratocaster::Event#dispatch.
    def to_hash
      return {} unless @repo
      {
        event_type: EVENT_TYPE,
        repo: @repo,
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
      targets_for @repo
    end

    # Builds the event's payload.
    #
    # Returns a Hash.
    def payload
      { ref: @ref, ref_type: @ref_type, pusher_type: @pusher_type }
    end

    # Builds the event's unique URL.
    #
    # Returns a String URL.
    def url
      "/" # no url because you deleted it!
    end
  end
end
