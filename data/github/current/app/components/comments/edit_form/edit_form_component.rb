# typed: true
# frozen_string_literal: true

module Comments
  module EditForm
    class EditFormComponent < ApplicationComponent
      include GhostPilotHelper

      attr_reader :comment, :comment_context, :textarea_id, :saved_reply_context, :slash_commands_enabled, :slash_commands_surface, :current_repository

      def initialize(comment:, comment_context:, textarea_id:, saved_reply_context: nil, slash_commands_enabled: false, slash_commands_surface: nil, tasklist_blocks_enabled: false, current_repository: nil)
        @comment = if comment.is_a?(Issue::Adapter::IssueAdapter)
          comment.issue
        elsif comment.is_a?(Issue::Adapter::CommentAdapter)
          comment.raw_object
        else
          comment
        end
        @comment_context = comment_context
        @textarea_id = textarea_id
        @saved_reply_context = saved_reply_context
        @slash_commands_enabled = slash_commands_enabled
        @slash_commands_surface = slash_commands_surface
        @tasklist_blocks_enabled = tasklist_blocks_enabled
        @current_repository = current_repository
      end

      def subject_type
        if comment_for_gist?
          "Gist"
        elsif comment_for_pull_request?
          "PullRequest"
        elsif comment_for_issue?
          "Issue"
        else
          nil
        end
      end

      def preview_subject
        if comment_for_gist?
          comment.gist.name
        else
          nil
        end
      end

      sig { returns(T.nilable(PullRequest)) }
      def pull_request
        if comment_for_issue_comment?
          comment.issue.pull_request
        elsif comment_for_pull_request? || comment_for_pull_request_review? || comment_for_pull_request_review_comment?
          comment.pull_request
        end
      end

      def issue
        if comment_for_issue_comment?
          comment.issue.id # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        elsif comment_for_issue?
          comment.id
        else
          nil
        end
      end

      def required
        true
      end

      def data_preview_url
        preview_path(
          repository: comment.try(:repository_id),
          subject_type: subject_type,
          subject: preview_subject,
          markdown_unsupported: comment.created_via_email,
          issue: issue,
          pull_request: pull_request&.id)
      end

      def preview_side
        return false unless comment_for_pull_request_review_comment?

        comment.pull_request_review_thread&.position_data&.diff_side
      end

      # Public: tasklist blocks are only available on the Issue OP and only when
      # the feature flag is enabled.
      #
      # Returns a Boolean.
      sig { returns(T::Boolean) }
      def tasklist_blocks_enabled?
        comment_for_issue? && @tasklist_blocks_enabled
      end

      # Public: Determines if Copilot PR summarization features should be enabled
      # for this comment context.
      #
      # Returns true if:
      # - User has Copilot for PRs enabled, AND
      # - Either it's a PR description (always enabled) OR it's a PR comment with the feature flag enabled
      #
      # Returns a Boolean.
      sig { returns(T::Boolean) }
      def copilot_for_prs_enabled?
        PullRequests::Copilot.copilot_for_prs_enabled?(current_copilot_user_v2) &&
        (
          comment_for_pull_request? ||
          (comment_for_issue_comment_on_pull_request? && FeatureFlag.vexi.enabled?(:pr_summary_comments, current_user, default: true))
        )
      end

      sig { returns(T::Boolean) }
      def copilot_text_completion_enabled?
        with_database_error_fallback(fallback: false) do
          comment_for_pull_request? && ghost_pilot_available?
        end
      end

      def copilot_text_completion_description
        if comment_for_pull_request?
          "Pull Request Description"
        elsif comment_for_issue_comment_on_pull_request?
          "Pull Request Comment"
        elsif comment_for_pull_request_review?
          "Pull Request Review"
        elsif comment_for_pull_request_review_comment?
          "Pull Request Review Comment"
        end
      end

      private

      sig { returns(T::Boolean) }
      memoize def comment_for_issue?
        comment.is_a?(Issue) && !comment.pull_request?
      end

      sig { returns(T::Boolean) }
      memoize def comment_for_pull_request?
        comment.is_a?(Issue) && comment.pull_request?
      end

      sig { returns(T::Boolean) }
      memoize def comment_for_issue_comment?
        comment.is_a?(IssueComment)
      end

      sig { returns(T::Boolean) }
      memoize def comment_for_gist?
        comment.is_a?(GistComment)
      end

      sig { returns(T::Boolean) }
      memoize def comment_for_pull_request_review?
        comment.is_a?(PullRequestReview)
      end

      sig { returns(T::Boolean) }
      memoize def comment_for_pull_request_review_comment?
        comment.is_a?(PullRequestReviewComment)
      end

      sig { returns(T::Boolean) }
      memoize def comment_for_issue_comment_on_pull_request?
        comment_for_issue_comment? && comment.issue.pull_request?
      end
    end
  end
end
