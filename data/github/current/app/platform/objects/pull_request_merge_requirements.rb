# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestMergeRequirements < Platform::Objects::Base
      description "A pull request's merge requirements"

      feature_flag :pull_request_merge_requirements_api

      required_capabilities [:mobile_only_schema_mask]

      def self.async_api_can_access?(permission, merge_requirements)
        permission.typed_can_access?("PullRequest", merge_requirements.pull_request)
      end

      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("PullRequest", object.pull_request)
      end

      field :commit_author, String, "The email address to use as author of a merge commit", null: false, method: :default_commit_author_email

      field :commit_message_headline, String, "The commit message headline of the merge commit", null: true

      field :commit_message_body, String, "The commit message body of the merge commit", null: true

      field :possible_commit_author_emails, [String], "The possible email addresses to use as author of a merge commit", null: false

      field :state, Enums::PullRequestMergeRequirementsState, "Whether the pull request is currently able to be merged", null: false

      field :conditions, [Interfaces::PullRequestMergeCondition], "The conditions for merging this pull request", null: false
    end
  end
end
