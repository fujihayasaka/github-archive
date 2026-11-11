# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ReviewStatusHovercardContext < Objects::Base
      implements Interfaces::HovercardContext
      description <<~DESCRIPTION
        A hovercard context with a message describing the current code review state of the pull
        request.
      DESCRIPTION
      scopeless_tokens_as_minimum

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        # object is a  IssueOrPullRequestHovercard::Contexts:ReviewStatus
        # .async_resolve returns nil if issue_or_pull_request is not a PullRequest, so we assume a PullRequest Object
        pull = object.issue_or_pull_request
        permission.async_repo_and_org_owner(pull).then do |repo, org|
          permission.access_allowed?(:read_pull_request_hovercard, repo: repo, current_org: org, resource: pull, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # object is a  IssueOrPullRequestHovercard::Contexts:ReviewStatus
        # .async_resolve returns nil if issue_or_pull_request is not a PullRequest, so we assume a PullRequest Object
        pull = object.issue_or_pull_request
        permission.typed_can_see?("PullRequest", pull)
      end

      field :review_decision, Enums::PullRequestReviewDecision, null: true,
        description: "The current status of the pull request with respect to code review."
    end
  end
end
