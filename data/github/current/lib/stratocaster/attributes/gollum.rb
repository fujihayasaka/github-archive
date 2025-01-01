# typed: false
# frozen_string_literal: true

module Stratocaster
  class Attributes::Gollum < Attributes
    EVENT_TYPE = "GollumEvent".freeze

    # Initializes the attributes for this event.
    #
    # actor_id - The ID of the User that made the change.
    # repo_id  - The ID of the Repository.
    # updates  - Array of Hashes describing the updated pages.
    #            :action    - String action on the wiki page.
    #            :page_name - String GitHub::Unsullied::Page name.
    #            :sha       - String SHA of the update.
    #
    # Returns nothing.
    def from(actor_id, repo_id, updates)
      return unless @repo  = Repository.find_by_id(repo_id)
      return unless @actor = User.find_by_id(actor_id)
      @updates = updates.map do |hash|
        hash.symbolize_keys.tap do |h|
          h[:page] = find_page(h)
        end
      end
    end

    # Converts a saved Event into the args necessary to get the other
    # attributes for this event type.
    #
    # event - A saved Stratocaster::Event instance.
    #
    # Returns nothing
    def from_event(event)
      return unless @repo = event.repo_record
      @actor = event.sender_record
      payload = event.payload.deep_symbolize_keys

      @updates = if payload.key?(:page_name) # legacy
        [
          action: event.action,
          sha: payload[:sha],
          page: find_page(payload),
        ]
      else
        payload[:pages].map do |page_hash|
          {
            action: page_hash[:action],
            sha: page_hash[:sha],
            page: find_page(page_hash),
          }
        end
      end
    end

    # Builds the Stratocaster::Event attribute hash.
    #
    # Returns a Hash of attributes for Stratocaster::Event#dispatch.
    def to_hash
      return {} unless @repo && @actor
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
      {
        pages: @updates.map do |hash|
          {
            page_name: hash[:page].name,
            title: hash[:page].title,
            summary: hash[:page].summary,
            action: hash[:action],
            sha: hash[:sha],
            html_url: url(hash[:page]),
          }
        end,
      }
    end

    # Builds the event's unique URL. This will be without the host url
    # because staff/enterprise environments can have different domains, and the
    # event data will be cached.
    #
    # Returns a String URL.
    def url(page = @updates.present? ? @updates.first[:page] : nil)
      return "/" unless @repo && page
      "%s/wiki/%s" % [
        @repo.permalink(include_host: false),
        u(GitHub::Unsullied::Page.cname(page.name))]
    end

    private

    def find_page(page_hash)
      @repo.unsullied_wiki.pages.find(page_hash[:page_name], page_hash[:sha]) ||
        @repo.unsullied_wiki.pages.find(page_hash[:page_name])
    end
  end
end
