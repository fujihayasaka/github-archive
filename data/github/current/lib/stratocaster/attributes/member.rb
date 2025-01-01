# typed: false
# frozen_string_literal: true

module Stratocaster
  class Attributes::Member < Attributes
    EVENT_TYPE = "MemberEvent".freeze

    # Initializes the attributes for this event.
    #
    # repo_id   - The Integer ID of the Repository that the User was added to.
    # member_id - The Integer ID of the User that was added.
    # actor_id  - The Integer ID of the User that added the member.
    # action    - The Symbol action name.
    #
    # Returns nothing.
    def from(repo_id, member_id, actor_id, action)
      @action = action

      # if we're removing a member, don't show it. don't cause drama.
      return if @action == :removed

      return unless @repo   = Repository.find_by_id(repo_id)
      return unless @member = User.find_by_id(member_id)
      nil unless @actor  = User.find_by_id(actor_id)
    end

    # Converts a saved Event into the args necessary to get the other
    # attributes for this event type.
    #
    # event - A saved Stratocaster::Event instance.
    #
    # Returns nothing
    def from_event(event)
      @repo   = event.repo_record
      @member = User.find_by_id(event.member_id)
      @actor  = event.sender_record
      @action = event.action.to_sym
    end

    # Builds the Stratocaster::Event attribute hash.
    #
    # Returns a Hash of attributes for Stratocaster::Event#dispatch.
    def to_hash
      # if we're removing a member, don't show it. don't cause drama.
      return {} unless @action != :removed && @repo && @member && @actor
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
      return [] unless @repo&.public?
      targets_for @repo, @member
    end

    # Builds the event's payload.
    #
    # Returns a Hash.
    def payload
      {
        member: Api::Serializer.serialize(:user_hash, @member),
        action: @action,
      }
    end

    # Builds the event's unique URL. This will be without the host url
    # because staff/enterprise environments can have different domains, and the
    # event data will be cached.
    #
    # Returns a String URL.
    def url
      return "/" unless @repo
      @repo.permalink(include_host: false)
    end
  end
end
