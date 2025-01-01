# typed: false
# frozen_string_literal: true

module Stratocaster
  class Attributes::PullRequest < Attributes
    include Stratocaster::Attributes::Issues::ActionMetadata

    EVENT_TYPE = "PullRequestEvent".freeze

    # Initializes the attributes for this event.
    #
    # action   - The String action triggered on the Pull Request.
    # pull_id  - The Integer ID of the Pull Request.
    # actor_id - The Integer ID of the User that triggered the event.
    #
    # Returns nothing.
    def from(action, pull_id, actor_id, meta = {})
      return unless @pull = ::PullRequest.find_by_id(pull_id)
      @actor = actor_id ? User.find_by_id(actor_id) : @pull.user
      @action = action
      @meta   = expand_metadata(**meta)
    end

    # Converts a saved Event into the args necessary to get the other
    # attributes for this event type.
    #
    # event - A saved Stratocaster::Event instance.
    #
    # Returns nothing
    def from_event(event)
      @action = event.action.to_sym
      @pull   = ::PullRequest.find_by_id(event.pull_request_id)
      @actor  = event.sender_record
      @meta   = metadata_from_payload(event.payload.deep_symbolize_keys)
    end

    # Builds the Stratocaster::Event attribute hash.
    #
    # Returns a Hash of attributes for Stratocaster::Event#dispatch.
    def to_hash(hash = {})
      return hash unless @pull

      # We might be in a race with destruction
      return hash unless @pull.repository

      # We can't do much if eiher side of the PR disappears
      return hash unless @pull.head_user && @pull.base_user

      unless dispatchable_action?
        hash[:skip_dispatching] = true
      end

      hash.update \
        event_type: EVENT_TYPE,
        repo: @pull.repository,
        sender: @actor,
        url: url,
        payload: payload
    end

    # Builds the list of targets for an event.
    #
    # timeline_type - an optional String for the timeline that will be shown
    #
    # Returns an Array of User IDs.
    def targets(timeline_type = nil)
      return [] unless @pull&.repository
      targets_for @pull.repository
    end

    # Builds the event's payload.
    #
    # Returns a Hash.
    def payload
      {
        action: @action,
        number: @pull.number,
        pull_request: Api::Serializer.serialize(:pull_request_hash, @pull, full: true),
      }.merge(@meta)
    end

    # Builds the event's unique URL. This will be without the host url
    # because staff/enterprise environments can have different domains, and the
    # event data will be cached.
    #
    # Returns a String URL.
    def url
      if @pull.try(:repository) && @pull.issue
        @pull.permalink(include_host: false)
      else
        "/"
      end
    end
  end
end
