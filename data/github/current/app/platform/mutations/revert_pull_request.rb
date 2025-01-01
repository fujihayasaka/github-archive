# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RevertPullRequest < Platform::Mutations::Base
      description "Create a pull request that reverts the changes from a merged pull request."

      minimum_accepted_scopes ["repo"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :pull_request_id, ID, "The ID of the pull request to revert.", required: true, loads: Objects::PullRequest
      argument :title, String, description: "The title of the revert pull request.", required: false
      argument :body, String, description: "The description of the revert pull request.", required: false
      argument :draft, Boolean, description: "Indicates whether the revert pull request should be a draft.", required: false, default_value: false

      field :revert_pull_request, Objects::PullRequest, "The new pull request that reverts the input pull request.", null: true

      field :pull_request, Objects::PullRequest, "The pull request that was reverted.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull_request:, **inputs)
        pull_request.async_base_repository.then do |repository|
          permission.async_owner_if_org(repository).then do |org|
            pull_request.async_pushable_repo_for(permission.viewer).then do |pushable_repo|
              !!pushable_repo &&
              permission.access_allowed?(:revert_pull_request, repo: pushable_repo, resource: pull_request, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
            end
          end
        end
      end

      def resolve(pull_request:, draft:, **inputs)
        viewer = context[:viewer]

        title = inputs[:title] || ""
        body = inputs[:body] || ""

        pull_request.async_base_repository.then do |repository|
          reflog_data = {
            real_ip: context[:ip],
            user_agent: context[:user_agent],
            repo_name: repository.name_with_owner, # rubocop:disable GitHub/DoNotAllowNameWithOwner
            repo_public: repository.public?,
            user_login: viewer.login, # rubocop:disable GitHub/DoNotAllowLogin
            from: GitHub.context[:from],
            via: "RevertPullRequest mutation",
            pr_author_login: pull_request.safe_user.login, # rubocop:disable GitHub/DoNotAllowLogin
          }
          revert_branch, error = GitHub.dogstats.distribution_time("pull_requests.mutations.revert_pr.create_revert") do
            pull_request.revert(viewer, reflog_data, timeout: 8)
          end

          if !revert_branch
            raise Errors::Unprocessable.new(error.to_s.humanize)
          end

          base_label, head_label =
            if revert_branch.repository == pull_request.base_repository
              [pull_request.base_ref_name, revert_branch.name]
            else
              ["#{pull_request.base_label(username_qualified: true)}", "#{revert_branch.repository.owner.display_login}:#{revert_branch.name}"]
            end

          if title.empty?
            title = "Revert \"#{pull_request.title}\""
          end

          if body.empty?
            body = "Reverts #{pull_request.base_repository.name_with_display_owner}##{pull_request.number}"
          end

          options = {
            base: base_label,
            head: head_label,
            user: viewer,
            title: title,
            body: body,
            user_id: viewer.display_login,
            repository_id: repository.id,
            draft: draft
          }

          revert_pull_request = GitHub.dogstats.distribution_time("pull_requests.mutations.revert_pr.create_pull") do
            PullRequest.create_for!(repository, options)
          end

          GlobalInstrumenter.instrument("pull_request.user_action",
            {
              user_id: viewer.id,
              repository_id: repository.id,
              pull_request_id: pull_request.id,
              category: "graphql",
              action: "revert"
            }
          )

          {
            revert_pull_request: revert_pull_request,
            pull_request: pull_request
          }

        rescue ActiveRecord::RecordInvalid => e
          raise Errors::Unprocessable.new("Pull request could not be reverted. #{e.message}")
        rescue Git::Ref::HookFailed => e
          raise Errors::Unprocessable.new("Pull request could not be reverted.")
        end
      end
    end
  end
end
