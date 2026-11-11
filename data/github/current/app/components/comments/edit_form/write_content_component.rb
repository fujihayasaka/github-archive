# typed: true
# frozen_string_literal: true

module Comments
  module EditForm
    class WriteContentComponent < ApplicationComponent
      include UploadHelper

      attr_reader :comment, :required, :textarea_id, :comment_context, :slash_commands_surface
      delegate :spamurai_form_signals, :issue_suggestions_params, :mention_suggestions_params, to: :helpers

      def initialize(comment:, required:, textarea_id:, comment_context:, slash_commands_surface: nil)
        @comment = comment
        @required = required
        @textarea_id = textarea_id
        @comment_context = comment_context
        @slash_commands_surface = slash_commands_surface
      end

      memoize def body
        if comment_for_issue? && TasklistBlocks::UrlExpander.enabled?(@comment)
          TasklistBlocks::UrlExpander.expand(@comment)
        else
          @comment.body
        end
      end

      def subject
        if !has_repository?
          nil
        elsif comment_for_pull_request? || comment_for_issue?
          comment
        elsif comment_for_pull_request_review? || comment_for_pull_request_review_comment?
          comment.pull_request
        elsif comment_for_issue_comment?
          comment.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        else
          nil
        end
      end

      def input_name
        if comment_for_gist?
          "gist_comment"
        elsif comment_for_commit_comment?
          "commit_comment"
        elsif comment_for_pull_request_review?
          "pull_request_review"
        elsif comment_for_pull_request_review_comment?
          "pull_request_review_comment"
        elsif comment_for_issue_comment?
          "issue_comment"
        elsif comment_for_pull_request?
          "pull_request"
        elsif comment_for_issue?
          "issue"
        elsif comment_for_repository_advisory_comment?
          "repository_advisory_comment"
        else
          nil
        end
      end

      def file_attachment_tag(**args, &block)
        UploadHelper.instance_method(:file_attachment_tag).bind(self).call(**args, &block)
      end

      def emoji_suggestions
        comment_for_gist? ? suggestions_user_gist_path(comment.gist.user_param, comment.gist) : emoji_suggestions_path
      end

      def attachment_opts
        if comment_for_gist?
          { "data-subject-type": "Gist", "data-subject-param": comment.gist }
        elsif has_repository?
          { "data-upload-repository-id" => repository_database_id }
        else
          {}
        end
      end

      def expander_keys
        [
          ":",
          comment_for_gist? ? "@" : nil,
          has_repository? ? "@ #" : nil
        ].compact.join(" ")
      end

      def subject_gid
        if comment_for_gist?
          comment.subject_gid
        else
          comment.respond_to?(:subject_id) ? comment.subject_id : comment.global_relay_id
        end
      end

      def has_repository?
        comment.respond_to?(:repository)
      end

      memoize def comment_for_gist?
        comment.is_a?(GistComment)
      end

      private

      def repository_database_id
        comment.repository.is_a?(ActiveRecord::Base) ? comment.repository.id : comment.repository.database_id
      end

      memoize def comment_for_commit_comment?
        comment.is_a?(CommitComment)
      end

      memoize def comment_for_pull_request_review?
        comment.is_a?(PullRequestReview)
      end

      memoize def comment_for_pull_request_review_comment?
        comment.is_a?(PullRequestReviewComment)
      end

      memoize def comment_for_issue_comment?
        comment.is_a?(IssueComment) || comment.is_a?(Issue::Adapter::CommentAdapter)
      end

      memoize def comment_for_issue?
        (comment.is_a?(Issue) && !comment.pull_request?) ||
          comment.is_a?(Issue::Adapter::IssueAdapter)
      end

      memoize def comment_for_pull_request?
        comment.is_a?(Issue) && comment.pull_request?
      end

      memoize def comment_for_repository_advisory_comment?
        comment.is_a?(RepositoryAdvisoryComment) ||
          comment.is_a?(RepositoryAdvisory::Adapter::CommentAdapter)
      end
    end
  end
end
