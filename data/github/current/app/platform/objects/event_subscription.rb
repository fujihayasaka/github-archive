# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    # This would normally be called `Subscription` but that name is
    # already taken by a domain object.
    class EventSubscription < Platform::Objects::Base
      def self.authorized?(*)
        super.sync # rubocop:disable GitHub/DontSyncInsideFields
      end

      def self.async_viewer_can_see?(*)
        # Viewers don't need to see this
        false
      end

      def self.async_api_can_access?(*)
        # Subscriptions should never be accessible via api
        false
      end

      visibility :internal

      description "The root object for implementing GraphQL subscriptions."

      # Pull request subscriptions
      field :pull_request_title_updated, subscription: Subscriptions::PullRequestTitleUpdated, description: "The pull request title was updated"
      field :pull_request_comments_updated, subscription: Subscriptions::PullRequestCommentsUpdated, description: "The pull request comments were updated"
      field :pull_request_status_updated, subscription: Subscriptions::PullRequestStatusUpdated, description: "The pull request status was updated"
      field :pull_request_review_decision_updated, subscription: Subscriptions::PullRequestReviewDecisionUpdated, description: "The pull request review decision was updated"

      # Commit subscriptions
      field :commit_checks_updated, subscription: Subscriptions::CommitChecksUpdated, description: "The commit checks were updated"

      # issue subscriptions
      field :issue_updated, subscription: Subscriptions::IssueUpdated, description: "A property of an issue was updated"

      # job status subscriptions
      field :job_status_updated, subscription: Subscriptions::JobStatusUpdated, description: "A job status was updated"
    end
  end
end
