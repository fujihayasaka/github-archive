# typed: false
# frozen_string_literal: true

module Stratocaster
  class Attributes::Create < Attributes
    EVENT_TYPE = "CreateEvent".freeze

    # Initializes the attributes for this event.
    #
    # repo_id   - Integer Repository ID or a Repository
    # ref       - The String git ref that was created.  nil if just a
    #             Repository was created.
    # pusher_id - Optional ID of the User that pushed a ref, or nil.
    #
    # Returns nothing.
    def from(repo_id, ref = nil, pusher_id = nil)
      return unless @repo = if repo_id.is_a?(Repository)
                      repo_id
                    elsif FeatureFlag.vexi.enabled?(:repos_by_id_lib, default: false)
                      Repositories.domain.by_id(repo_id)
                    else
                      Repository.find_by_id(repo_id)
                    end
      @ref_type = RefType.from_ref(ref, default: RefType::REPOSITORY)
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
      return [] unless @repo
      targets_for @repo, repository_ref_type? && @repo.public? && @actor
    end

    # Builds the event's payload.
    #
    # Returns a Hash.
    def payload
      {
        ref: @ref,
        ref_type: @ref_type,
        master_branch: @repo.default_branch,
        description: @repo.description,
        pusher_type: @pusher_type,
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
      "#{@repo.permalink(include_host: false)}/#{@ref_type.path_segment}/#{u @ref}"
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

    def repository_ref_type?
      @ref_type == RefType::REPOSITORY
    end
  end
end
