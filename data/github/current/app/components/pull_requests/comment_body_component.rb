# typed: true
# frozen_string_literal: true

module PullRequests
  class CommentBodyComponent < ApplicationComponent
    attr_reader :comment, :body_html, :classes

    PLACEHOLDER_MESSAGE = GitHub::HTMLSafeString.make("No description provided.")

    renders_one :actions

    def initialize(comment:, body_html:, classes: "d-block css-overflow-wrap-anywhere")
      @comment = comment
      @body_html = body_html
      @classes = classes
    end

    def body_classes
      class_names(
        "comment-body markdown-body js-comment-body soft-wrap",
        # Containing the text selection to the boundaries of this element; see https://developer.mozilla.org/en-US/docs/Web/CSS/user-select %>
        "user-select-contain",
        classes,
        "email-format" => comment.created_via_email
      )
    end

    def pull_request
      comment.pull_request if comment.respond_to?(:pull_request)
    end

    def comment_permalink
      # Use the comment's built-in permalink method if available
      # Different comment types (IssueComment, PullRequestReviewComment, etc.)
      # implement their own permalink logic
      if comment.respond_to?(:permalink)
        comment.permalink
      elsif comment.respond_to?(:full_permalink) # CommitComment case
        comment.full_permalink
      end
    end
  end
end
