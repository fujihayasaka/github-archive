# typed: false
# frozen_string_literal: true

module Stratocaster
  class Attributes::Issues < Attributes
    autoload :ActionMetadata, "stratocaster/attributes/issues/action_metadata"

    include Stratocaster::Attributes::Issues::ActionMetadata

    EVENT_TYPE = "IssuesEvent".freeze

    # Initializes the attributes for this event.
    #
    # action   - String action triggered on the Issue.
    # issue_id - Integer ID of the Issue being updated.
    # actor_id - Optional Integer ID of the User performing the action.
    #
    # Returns nothing.
    def from(action, issue_id, actor_id, meta = {})
      return unless @issue = Issue.find_by_id(issue_id)
      @actor  = actor_id ? User.find_by_id(actor_id) : @issue.user
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
      @actor  = event.sender_record
      @issue = Issue.find_by_id(event.issue_id)
      @meta = metadata_from_payload event.payload.deep_symbolize_keys
    end

    # Builds the Stratocaster::Event attribute hash.
    #
    # Returns a Hash of attributes for Stratocaster::Event#dispatch.
    def to_hash(hash = {})
      return hash unless @issue && @issue.repository.present?

      unless dispatchable_action?
        hash[:skip_dispatching] = true
      end

      hash.update \
        event_type: EVENT_TYPE,
        repo: @issue.repository,
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
      targets_for @issue
    end

    # Builds the event's payload.
    #
    # Returns a Hash.
    def payload
      {
        action: @action,
        issue: Api::Serializer.serialize(:issue_hash, @issue),
        legacy: { action: @action, issue: @issue.id, number: @issue.number },
      }.merge(@meta)
    end

    # Builds the event's unique URL. This will be without the host url
    # because staff/enterprise environments can have different domains, and the
    # event data will be cached.
    #
    # Returns a String URL.
    def url
      @issue.try(:repository) ? @issue.permalink(include_host: false) : "/"
    end
  end
end
