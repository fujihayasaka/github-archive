# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class EnablePullRequestAutoMerge < Platform::Mutations::Base
      description "Enable the default auto-merge on a pull request."

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, "ID of the pull request to enable auto-merge on.", required: true, loads: Objects::PullRequest
      argument :commit_headline, String, "Commit headline to use for the commit when the PR is mergable; if omitted, a default message will be used. NOTE: when merging with a merge queue any input value for commit headline is ignored.", required: false
      argument :commit_body, String, "Commit body to use for the commit when the PR is mergable; if omitted, a default message will be used. NOTE: when merging with a merge queue any input value for commit message is ignored.", required: false
      argument :merge_method, Enums::PullRequestMergeMethod, "The merge method to use. If omitted, defaults to `MERGE`. NOTE: when merging with a merge queue any input value for merge method is ignored.", required: false, default_value: :merge
      argument :merge_queue_method, Enums::MergeQueueMethod, "The merge queue method to use. If omitted, defaults to `GROUP`.", required: false, visibility: :internal
      argument :author_email, String, "The email address to associate with this merge.", required: false
      argument :expected_head_oid, Scalars::GitObjectID, "The expected head OID of the pull request.", required: false

      error_fields
      field :pull_request, Objects::PullRequest, "The pull request auto-merge was enabled on.", null: true
      field :actor, Interfaces::Actor, "Identifies the actor who performed the event.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        pull = inputs[:pull_request]
        permission.async_repo_and_org_owner(pull).then do |repo, org|
          pull.async_issue.then do |_issue|
            permission.access_allowed?(:enable_pull_request_auto_merge, repo: repo, resource: pull, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      def resolve(execution_errors:, **inputs)
        pull         = inputs[:pull_request]
        repository   = pull.repository
        author_email = inputs[:author_email]
        expected_head_oid = inputs[:expected_head_oid]
        merge_method = inputs[:merge_queue_method] || inputs[:merge_method]

        context[:permission].authorize_content(:pull_request, :auto_merge, repo: repository)

        check_database_resource_update_rate_limit!(resource: pull, current_user: context[:viewer])

        if author_email
          author_email_record = UserEmail.verified.where(user_id: context[:viewer].id, email: author_email)
          message = "#{context[:viewer].display_login} does not have a verified email, which is required to enable auto-merging."
          raise Errors::Unprocessable.new(message) unless author_email_record.exists?
        end

        if expected_head_oid
          raise Errors::MergeQueue::PullRequestHeadOidMismatch.new(pull) unless pull.head_sha == expected_head_oid
        end

        if !pull.auto_merge_request && !pull.in_merge_queue?
          AutoMergeRequest.enqueue!(
            pull_request: pull,
            user: context[:viewer],
            merge_method: merge_method,
            email: author_email ? author_email_record.first : nil,
            commit_title: inputs[:commit_headline],
            commit_message: inputs[:commit_body],
            remote_ip: context[:rails_request]&.remote_ip,
          )
        end

        {
          pull_request: pull,
          actor: context[:viewer],
          errors: [],
        }
      rescue AutoMergeRequest::Invalid => e
        raise Errors::Unprocessable.new(e.to_s)
      end
    end
  end
end
