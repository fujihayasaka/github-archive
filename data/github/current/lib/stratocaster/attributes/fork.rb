# typed: false
# frozen_string_literal: true

module Stratocaster
  class Attributes::Fork < Attributes
    EVENT_TYPE = "ForkEvent".freeze

    # Initializes the attributes for this event.
    #
    # child_id - Integer ID of the Repository fork.
    #
    # Returns nothing.
    def from(child_id)
      @child = if FeatureFlag.vexi.enabled?(:repos_by_id_lib, default: false)
        Repositories.domain.by_id(child_id)
      else
        Repository.find_by(id: child_id)
      end
    end

    # Converts a saved Event into the args necessary to get the other
    # attributes for this event type.
    #
    # event - A saved Stratocaster::Event instance.
    #
    # Returns nothing
    def from_event(event)
      from(event.forkee_id)
    end

    # Builds the Stratocaster::Event attribute hash.
    #
    # Returns a Hash of attributes for Stratocaster::Event#dispatch.
    def to_hash
      return unless @child
      {
        event_type: EVENT_TYPE,
        repo: parent,
        sender: @child.owner,
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
      return [] if @child.blank?

      targets_for(
        (@child.public? && @child.owner), parent&.owner_id)
    end

    # Builds the event's payload.
    #
    # Returns a Hash.
    def payload
      payload = { forkee: Api::Serializer.serialize(:repository_hash, @child).update(public: @child.public?) }

      if parent.present?
        payload.merge! \
          repository: {
            nwo: parent.nwo,
            description: parent.description,
            good_first_issue_issues_count: repo_good_first_issue_issues_count,
            help_wanted_issues_count: repo_help_wanted_issues_count,
            help_wanted_label_name: parent.help_wanted_label&.name,
            language_name: parent.primary_language_name,
            stargazers_count: parent.stargazer_count,
            updated_at: parent.updated_at.to_time.utc.xmlschema,
          }
      end

      payload
    end

    # Builds the event's unique URL. This will be without the host url
    # because staff/enterprise environments can have different domains, and the
    # event data will be cached.
    #
    # Returns a String URL.
    def url
      return "/" unless @child
      @child.permalink(include_host: false)
    end

    private

    def repo_good_first_issue_issues_count
      if parent.has_issues?
        repo_community_profile&.good_first_issue_issues_count
      else
        0
      end
    end

    def repo_help_wanted_issues_count
      if parent.has_issues?
        repo_community_profile&.help_wanted_issues_count
      else
        0
      end
    end

    def repo_community_profile
      return @repo_community_profile if defined? @repo_community_profile
      @repo_community_profile = parent.community_profile
    end

    def parent
      return @parent if defined?(@parent)
      @child.parent
    end
  end
end
