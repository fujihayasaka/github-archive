# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class AutoMergeRequest < Platform::Objects::Base
      description "Represents an auto-merge request for a pull request"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, auto_merge_request)
        permission.load_pull_and_issue(auto_merge_request).then do |pull|
          permission.async_repo_and_org_owner(auto_merge_request).then do |repo, org|
            pull.repository = repo # avoid association load down the line
            permission.access_allowed?(:get_auto_merge, repo: repo, resource: pull, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_repository.then do |repository|
          if repository.hide_from_user?(permission.viewer)
            false
          else
            permission.belongs_to_pull_request(object)
          end
        end
      end

      scopeless_tokens_as_minimum

      field :enabled_by, Interfaces::Actor, description: "The actor who created the auto-merge request.", null: true, method: :async_user
      field :commit_headline, String, description: "The commit title of the auto-merge request. If a merge queue is required by the base branch, this value will be set by the merge queue when merging", null: true, method: :commit_title
      field :commit_body, String, description: "The commit message of the auto-merge request. If a merge queue is required by the base branch, this value will be set by the merge queue when merging.", null: true, method: :commit_message
      field :merge_method, Enums::PullRequestMergeMethod, description: "The merge method of the auto-merge request. If a merge queue is required by the base branch, this value will be set by the merge queue when merging.", null: false, method: :minimal_merge_method

      field :author_email, String, description: "The email address of the author of this auto-merge request.", null: true
      def author_email
        @object.async_commit_email_address.then do |commit_email_address|
          if commit_email_address
            commit_email_address.email
          end
        end
      end

      field :enabled_at, Scalars::DateTime, description: "When was this auto-merge request was enabled.", null: true, method: :created_at

      field :pull_request, Objects::PullRequest, description: "The pull request that this auto-merge request is set against.", null: false
      def pull_request
        @object.async_pull_request.then do |pull_request|
          pull_request
        end
      end
    end
  end
end
