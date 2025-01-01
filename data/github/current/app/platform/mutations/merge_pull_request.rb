# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MergePullRequest < Platform::Mutations::Base
      description "Merge a pull request."

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, "ID of the pull request to be merged.", required: true, loads: Objects::PullRequest
      argument :commit_headline, String, "Commit headline to use for the merge commit; if omitted, a default message will be used.", required: false
      argument :commit_body, String, "Commit body to use for the merge commit; if omitted, a default message will be used", required: false
      argument :expected_head_oid, Scalars::GitObjectID, "OID that the pull request head ref must match to allow merge; if omitted, no check is performed.", required: false
      argument :merge_method, Enums::PullRequestMergeMethod, "The merge method to use. If omitted, defaults to 'MERGE'", required: false, default_value: :merge
      argument :author_email, String, "The email address to associate with this merge.", required: false

      error_fields
      field :pull_request, Objects::PullRequest, "The pull request that was merged.", null: true
      field :actor, Interfaces::Actor, "Identifies the actor who performed the event.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        pull        = inputs[:pull_request]
        permission.async_repo_and_org_owner(pull).then do |repo, org|
          pull.async_issue.then do |_issue|
            permission.access_allowed?(:merge_pull_request, repo: repo, resource: pull, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      def resolve(execution_errors:, **inputs)
        pull        = inputs[:pull_request]
        repository  = pull.repository

        context[:permission].authorize_content(:pull_request, :merge, repo: repository)

        if !context[:actor].can_have_granular_permissions? && !pull.async_viewer_can_update?(context[:viewer]).sync
          message = "#{context[:viewer].display_login} does not have permission to update the pull request #{pull.global_relay_id}."
          raise Errors::Forbidden.new(message)
        end

        unless repository.feature_enabled?(:better_merge_email_validation)
          if inputs[:author_email] && GitHub.email_verification_enabled?
            raise Errors::Unprocessable.new("Unverified email address") unless UserEmail.verified.where(user_id: context[:viewer].id, email: inputs[:author_email]).exists?
          end
        end

        method = inputs[:merge_method] || :merge

        # disable linters below because login and nwo are fine in reflog, not customer facing
        reflog_data = {
          real_ip: context[:ip],
          repo_name: repository.name_with_owner, # rubocop:disable GitHub/DoNotAllowNameWithOwner
          repo_public: repository.public?,
          user_login: context[:viewer].login, # rubocop:disable GitHub/DoNotAllowLogin
          user_agent: context[:user_agent],
          pr_author_login: pull.safe_user.login, # rubocop:disable GitHub/DoNotAllowLogin
          via: "pull request merge graphql mutation",
          from: GitHub.context[:from],
        }

        begin
          case result = PullRequests::Merge.call(
            pull_request: pull,
            user: context[:viewer],
            expected_head_sha: inputs[:expected_head_oid],
            commit_body: inputs[:commit_body],
            commit_title: inputs[:commit_headline],
            commit_author_email: inputs[:author_email],
            method:,
            reflog_data:,
          )
          when PullRequests::Merge::Success
            case inputs[:merge_method]
            when :rebase
              pull.base_repository.set_sticky_merge_method(context[:viewer], "rebase")
            when :squash
              pull.base_repository.set_sticky_merge_method(context[:viewer], "squash")
            else
              pull.base_repository.set_sticky_merge_method(context[:viewer], "merge_commit")
            end

            {
              pull_request: pull,
              actor: context[:viewer],
              errors: [],
            }
          when PullRequests::Merge::Failure
            if result.code == :workflow_policy_update_error
              raise Errors::Forbidden.new(result.error_message)
            else
              raise Errors::Unprocessable.new(result.error_message)
            end
          else
            T.absurd(result)
          end
        rescue Git::Ref::HookFailed => e
          message = "Could not merge because a Git pre-receive hook failed.\n\n#{e.message}"
          raise Errors::Unprocessable.new(message)
        end
      end
    end
  end
end
