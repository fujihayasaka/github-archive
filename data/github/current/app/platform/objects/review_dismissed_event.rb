# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ReviewDismissedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'review_dismissed' event on a given issue or pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, review_dismissed_event)
        permission.belongs_to_issue_event(review_dismissed_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rrde, :repo_id, :issue_id, :review_dismissed_event_id]
      ], as: "RDE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rrde,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          review_dismissed_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp

      implements Interfaces::UniformResourceLocatable


      # TODO: remove this when the declaration in TimelineEvent becomes public
      database_id_field

      field :pull_request, Objects::PullRequest, "PullRequest referenced by event.", method: :async_issue_or_pull_request, null: false

      field :dismissal_message, String, "Identifies the optional message associated with the 'review_dismissed' event.", method: :async_message, null: true

      field :dismissal_message_html, String, "Identifies the optional message associated with the event, rendered to HTML.", method: :async_message_html, null: true

      field :review, Objects::PullRequestReview, description: "Identifies the review associated with the 'review_dismissed' event.", null: true

      def review
        @object.async_issue_event_detail.then do |issue_event_detail|
          Loaders::ActiveRecord.load(::PullRequestReview, issue_event_detail.pull_request_review_id).then do |review|
            next unless review

            context[:permission].typed_can_see?("PullRequestReview", review).then do |can_read|
              review if can_read
            end
          end
        end
      end

      field :previous_review_state, Enums::PullRequestReviewState, description: "Identifies the previous state of the review with the 'review_dismissed' event.", null: false

      def previous_review_state
        @object.async_issue_event_detail.then do |issue_event_detail|
          state_was = issue_event_detail.pull_request_review_state_was
          # This field probably should have been nullable, but there are at
          # least some conditions where a review dismissed event won't be associated
          # with a concrete review, see https://github.com/github/coding/issues/896.
          state_was ||= ::PullRequestReview.state_value(:commented)
          ::PullRequestReview.state_name(state_was).to_s
        end
      end

      field :pull_request_commit, PullRequestCommit, description: "Identifies the commit which caused the review to become stale.", null: true

      def pull_request_commit
        @object.async_issue_event_detail.then do |detail|
          next unless detail.after_commit_oid

          @object.async_issue_or_pull_request.then do |pull|
            next unless pull.is_a?(::PullRequest)

            pull.async_load_pull_request_commit(detail.after_commit_oid)
          end
        end
      end

      url_fields description: "The HTTP URL for this review dismissed event." do |event|
        event.async_path_uri
      end
    end
  end
end
