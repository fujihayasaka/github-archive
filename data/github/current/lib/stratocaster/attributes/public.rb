# typed: false
# frozen_string_literal: true

module Stratocaster
  class Attributes::Public < Attributes
    EVENT_TYPE = "PublicEvent".freeze

    # How long to delay before writing 'make public' events into timelines.
    # If the repo becomes private or is removed entirely within an hour the
    # event will not be written at all (see #from)
    FANOUT_DELAY = 1.hour

    # Initializes the attributes for this event.
    #
    # repo_id  - Integer ID of a Repository
    # actor_id - Integer ID of the User that made the Repository public.
    #
    # Returns nothing.
    def from(repo_id, actor_id = nil)
      return unless @repo = Repository.public_scope.find_by_id(repo_id)

      @actor = actor_id ? User.find_by_id(actor_id) : @repo.owner
    end

    # Converts a saved Event into the args necessary to get the other
    # attributes for this event type.
    #
    # event - A saved Stratocaster::Event instance.
    #
    # Returns nothing
    def from_event(event)
      @repo  = event.repo_record
      @actor = event.sender_record
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
      targets_for @repo, @actor
    end

    # Builds the event's payload.
    #
    # Returns a Hash.
    def payload
      {
        repository: {
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
