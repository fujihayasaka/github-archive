# typed: true
# frozen_string_literal: true

module Stratocaster
  class Attributes::Release < Attributes
    EVENT_TYPE = "ReleaseEvent".freeze

    # Initializes the attributes for this event.
    #
    # release_id - Integer ID of a Release
    #
    # Returns nothing.
    def from(release_id)
      @release = ::Releases::Public.load_release(release_id) if release_id
    end

    def from_event(event)
      from event.release_id
    end

    # Builds the Stratocaster::Event attribute hash.
    #
    # Returns a Hash of attributes for Stratocaster::Event#dispatch.
    def to_hash
      return {} unless @release
      {
        event_type: EVENT_TYPE,
        repo: @release.repository,
        sender: @release.author,
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
      return [] unless @release && @release.repository
      targets_for(@release)
    end

    # Builds the event's payload.
    #
    # Returns a Hash.
    def payload
      short_description_html_info = @release.short_description_html_info
      {
        action: :published,
        release: Api::Serializer.serialize(:release_hash, @release, { include_mentions: true }).merge({
          short_description_html: short_description_html_info[:html],
          is_short_description_html_truncated: short_description_html_info[:truncated?],
        })
      }

    end

    # Builds the event's unique URL. This will be without the host url
    # because staff/enterprise environments can have different domains, and the
    # event data will be cached.
    #
    # Returns a String URL.
    def url
      @release.permalink(include_host: false) || "/"
    end
  end
end
