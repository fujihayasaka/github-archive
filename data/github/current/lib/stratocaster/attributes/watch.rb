# typed: false
# frozen_string_literal: true

module Stratocaster
  class Attributes::Watch < Attributes
    EVENT_TYPE = "WatchEvent".freeze

    # Initializes the attributes for this event.
    #
    # starred_type - The string representing the class of the starred object.
    #                Either a Topic or a Repository.
    # starred_id   - The Integer ID of the Repository or Topic being watched.
    # actor_id     - The Integer ID of the User watching the Repository.
    # action       - Symbol name of the action.
    #
    # Returns nothing.
    def from(starred_id, actor_id, action, starred_type = Star::STARRABLE_TYPE_REPOSITORY)
      return if starred_type == Star::STARRABLE_TYPE_TOPIC
      return unless @repo  = Repository.find_by_id(starred_id)
      return unless @actor = User.find_by_id(actor_id)
      @action = action
    end

    # Converts a saved Event into the args necessary to get the other
    # attributes for this event type.
    #
    # event - A saved Stratocaster::Event instance.
    #
    # Returns nothing
    def from_event(event)
      @repo   = event.repo_record
      @actor  = event.sender_record
      @action = event.action
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
      return [] unless @repo&.owner
      targets_for @actor, @repo.owner.id if @repo.public?
    end

    # Builds the event's payload.
    #
    # Returns a Hash.
    def payload
      {
        action: @action,
        repository: {
          nwo: @repo.nwo,
          description: @repo.description,
          good_first_issue_issues_count: repo_good_first_issue_issues_count,
          help_wanted_issues_count: repo_help_wanted_issues_count,
          help_wanted_label_name: @repo.help_wanted_label&.name,
          language_name: @repo.primary_language_name,
          stargazers_count: @repo.stargazer_count,
          updated_at: @repo.updated_at.to_time.utc.xmlschema,
        },
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

    private

    def repo_good_first_issue_issues_count
      if @repo.has_issues?
        repo_community_profile&.good_first_issue_issues_count
      else
        0
      end
    end

    def repo_help_wanted_issues_count
      if @repo.has_issues?
        repo_community_profile&.help_wanted_issues_count
      else
        0
      end
    end

    def repo_community_profile
      return @repo_community_profile if defined? @repo_community_profile
      @repo_community_profile = @repo.community_profile
    end
  end
end
