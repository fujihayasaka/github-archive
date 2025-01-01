# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class PullRequestSerializer < IssueSerializer
      def scope
        PullRequest.preload(:user, :review_requests, close_issue_references: included_close_issue_reference_associations, issue: included_issue_associations)
      end

      def as_json(options = {})
        {
          type:                   "pull_request",
          url:                    url,
          user:                   user,
          repository:             repository,
          title:                  title,
          body:                   body,
          base:                   base,
          head:                   head,
          assignee:               assignee,
          assignees:              assignees,
          milestone:              milestone,
          labels:                 labels,
          reactions:              reactions,
          review_requests:        review_requests,
          close_issue_references: close_issue_references,
          work_in_progress:       work_in_progress,
          merged_at:              merged_at,
          closed_at:              closed_at,
          created_at:             created_at,
          merge_commit_sha:       merge_commit_sha,
        }
      end

      private

      def included_close_issue_reference_associations
        [:issue, :issue_repository]
      end

      def issue
        model.issue
      end

      def base
        {
          ref: model.display_base_ref_name,
          sha: model.base_sha,
          user: url_for_association(model, :base_user),
          repo: url_for_association(model, :base_repository),
        }
      end

      def head
        {
          ref: model.display_head_ref_name,
          sha: model.head_sha,
          user: url_for_association(model, :head_user),
          repo: url_for_association(model, :head_repository),
        }
      end

      def merged_at
        time(model.merged_at)
      end

      def review_requests
        model.review_requests.map do |review_request|
          {
            reviewer: url_for_model(review_request.reviewer),
            reviewer_type: review_request.reviewer_type,
            created_at: time(review_request.created_at),
            updated_at: time(review_request.updated_at),
            dismissed_at: time(review_request.dismissed_at),
          }
        end
      end

      def close_issue_references
        model.close_issue_references.map do |close_issue_reference|
          {
            issue: url_for_model(close_issue_reference.issue),
            issue_repository: url_for_model(close_issue_reference.issue_repository),
            actor: url_for_model(model.user),
            source: close_issue_reference.source,
            created_at: time(close_issue_reference.created_at)
          }
        end
      end

      def work_in_progress
        model.work_in_progress
      end

      def merge_commit_sha
        model.merge_commit_sha
      end
    end
  end
end
