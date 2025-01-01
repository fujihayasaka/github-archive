# typed: false
# frozen_string_literal: true

module Stratocaster
  class Attributes::Sponsor < Attributes
    EVENT_TYPE = "SponsorEvent".freeze

    # Initializes the attributes for this event. Sponsors has the idea of "linked sponsorships"
    # where an organization can pay with one account and specify another account be credited for
    # that sponsorship. We resolve these early before the event is saved.
    #
    # sponsor_id    - The Integer ID of the User funding the sponsorship.
    # maintainer_id - The Integer ID of the User being sponsored.
    #
    # Returns nothing.
    def from(sponsor_id, maintainer_id)
      return unless the_user_paying = User.find_by_id(sponsor_id)
      return unless @maintainer = User.find_by_id(maintainer_id)
      @sponsor = the_user_paying.sponsoring_parent_organization || the_user_paying
    end

    # Converts a saved Event into the args necessary to get the other
    # attributes for this event type.
    #
    # event - A saved Stratocaster::Event instance.
    #
    # Returns nothing
    def from_event(event)
      @maintainer = User.find_by(id: event.target_id)
      @sponsor  = event.sender_record
    end

    # Builds the Stratocaster::Event attribute hash.
    #
    # Returns a Hash of attributes for Stratocaster::Event#dispatch.
    def to_hash
      return {} unless @sponsor && @maintainer
      {
        event_type: EVENT_TYPE,
        sender: @sponsor,
        payload: payload,
      }
    end

    # Builds the list of targets for an event.
    #
    # timeline_type - an optional String for the timeline that will be shown
    #
    # Returns an Array of User IDs.
    def targets(timeline_type = nil)
      targets_for @sponsor, @maintainer.id
    end

    # Builds the event's payload.
    #
    # Returns a Hash.
    def payload
      {
        target: Api::Serializer.serialize(:user_hash, @maintainer, full: true),
        maintainer_id: @maintainer.id,
        sponsor_id: @sponsor.id,
      }
    end
  end
end
