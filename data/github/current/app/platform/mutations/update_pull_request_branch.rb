# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdatePullRequestBranch < Platform::Mutations::Base
      description "Merge or Rebase HEAD from upstream branch into pull request branch"

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, description: "The Node ID of the pull request.", required: true, loads: Objects::PullRequest
      argument :expected_head_oid, Scalars::GitObjectID, description: "The head ref oid for the upstream branch.", required: false
      argument :update_method, Enums::PullRequestBranchUpdateMethod, description: "The update branch method to use. If omitted, defaults to 'MERGE'", required: false

      field :pull_request, Objects::PullRequest, "The updated pull request.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull_request:, **inputs)
        permission.async_repo_and_org_owner(pull_request).then do |repo, org|
          permission.access_allowed? :update_pull_request, repo: repo, current_org: org, resource: pull_request, allow_integrations: true, allow_user_via_granular_actor: true
        end
      end

      def resolve(pull_request:, expected_head_oid: nil, update_method: T.must(Enums::PullRequestBranchUpdateMethod.values["MERGE"]).value)
        context[:permission].authorize_content(:pull_request, :update, repo: pull_request.repository)

        unless pull_request.async_viewer_can_update?(context[:viewer]).sync
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to update this pull request.")
        end

        begin
          # Check if the API call authorized by an integration, and if this integration is having write access to repo contents
          # Notes:
          # - This is a temp. fix to remedy https://github.com/github/coding/issues/2358
          # - We have https://github.com/github/coding/issues/2435 to resolve the core issue at `Repository::OrganizationsDependency#pushable_by?`
          # TODO: Remove this block once https://github.com/github/coding/issues/2435 is fixed
          unless PullRequest::RepoWriteAccessViaIntegrationAuthorizer.new(repo: pull_request.head_repository, actor: context[:viewer]).allow?
            GitHub.logger.info(
              "attempt to call the update-branch mutation without permission on head repo contents",
              "gh.request_id": GitHub.context[:request_id]
            )
            raise Errors::Forbidden.new("#{context[:viewer].display_login} doesn't have permission to update head repository")
          end

          if update_method == T.must(Enums::PullRequestBranchUpdateMethod.values["REBASE"]).value
            pull_request.rebase_head_on_base(
              user: context[:viewer],
              author_email: context[:viewer]&.default_author_email(pull_request.repository, pull_request.head_sha),
              expected_head_oid: expected_head_oid || pull_request.head_sha,
            )
          else
            pull_request.merge_base_into_head(
              user: context[:viewer],
              author_email: context[:viewer]&.default_author_email(pull_request.repository, pull_request.head_sha),
              expected_head_oid: expected_head_oid || pull_request.head_sha
            )
          end
        rescue PullRequest::RefMismatch
          raise Errors::Unprocessable.new("head sha didn't match the current head ref.")
        rescue PullRequest::MergeConflictError => e
          raise Errors::Unprocessable.new(e.message)
        rescue PullRequest::RebaseConflictError => e
          raise Errors::Unprocessable.new(e.message)
        rescue PullRequest::PermissionError => e
          raise Errors::Forbidden.new(e.message)
        rescue Git::Ref::WorkflowUpdatePolicyError => e
          raise Errors::Forbidden.new(e.message)
        end

        { pull_request: pull_request }
      end
    end
  end
end
