# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CommunityProfile < Platform::Objects::Base
      description "Information about a repository's community engagement."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_repository.then do |repo|
          permission.typed_can_access?("Repository", repo)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end

      visibility :internal

      scopeless_tokens_as_minimum

      field :help_wanted_issues_count, Integer, "Returns a count of how many open issues in the repository have the label 'help wanted'.", null: false

      field :good_first_issue_issues_count, Integer, null: false, description: <<~DESCRIPTION
        Returns a count of how many open issues in the repository have the label 'good first
        issue'.
      DESCRIPTION

      field :has_content_reports_enabled, Boolean, description: "Indicates if this repository allows reporting content to its maintainers. This feature is only available for organization owned repositories.", null: false

      def has_content_reports_enabled
        @object.async_repository.then do |repository|
          repository.async_tiered_reporting_explicitly_enabled?
        end
      end
    end
  end
end
