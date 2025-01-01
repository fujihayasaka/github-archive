# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RequestReviewFromCopilot < Platform::Mutations::Base
      description "Requests a code review from Copilot."
      visibility :internal

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, "The Node ID of the pull request to modify.", required: true, loads: Objects::PullRequest, as: :pull
      argument :re_request, Boolean, "Whether or not the request is a re-request", required: false, default_value: false, visibility: :internal

      field :success, Boolean, "Did the operation succeed?", null: true
      field :pull_request, Objects::PullRequest, "The pull request that is getting requests.", null: true
      field :actor, Interfaces::Actor, "Identifies the actor who performed the event.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull:, **inputs)
        permission.async_repo_and_org_owner(pull).then do |repo, org|
          permission.access_allowed?(:request_pull_request_review, repo: repo, resource: pull, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(pull:, **inputs)
        reviewer_app = Apps::Privileged.integration(:copilot_pull_request_reviewer)
        if reviewer_app.nil?
          raise Errors::ServiceUnavailable.new("Copilot pull request reviews are not configured.")
        end

        code_review_access = PullRequests::Copilot::CodeReviewAccess.new(actor: context[:viewer], current_repository: pull.repository)
        if !code_review_access.can_create_review_request?
          raise Errors::Forbidden.new("Viewer does not have access to copilot pull request reviews.")
        end

        unless pull.request_review_from(reviewers: [reviewer_app.bot], actor: context[:viewer], re_request: inputs[:re_request], append: inputs[:union])
          raise Errors::Unprocessable.new("Could not request a Copilot review.")
        end

        { success: true }
      end
    end
  end
end
