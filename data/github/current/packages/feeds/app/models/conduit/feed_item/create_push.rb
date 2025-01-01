# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::CreatePush < FeedItem::PushEvent
    # Display
    def action_string
      rollup? ? "pushed" : "created"
    end

    def description
      "#{actor} #{action_string} a branch"
    end

    def api_type
      "CreateEvent"
    end

    def payload
      {
        ref: ref,
        ref_type: ref_type,
        master_branch: repository.default_branch,
        description: repository.description,
        pusher_type: push.pusher.type,
        repository: {
          description: repository.description,
          good_first_issue_issues_count: repo_good_first_issue_issues_count,
          help_wanted_issues_count: repo_help_wanted_issues_count,
          help_wanted_label_name: repository.help_wanted_label&.name,
          language_name: repository.primary_language_name,
          stargazers_count: repository.stargazer_count,
          updated_at: repository.updated_at.to_time.utc.xmlschema,
        },
      }
    end

    private

    def repo_good_first_issue_issues_count
      repository.has_issues? ? repo_community_profile&.good_first_issue_issues_count : 0
    end

    def repo_help_wanted_issues_count
      repository.has_issues? ? repo_community_profile&.help_wanted_issues_count : 0
    end

    def repo_community_profile
      return @repo_community_profile if defined? @repo_community_profile

      @repo_community_profile = repository.community_profile
    end
  end
end
