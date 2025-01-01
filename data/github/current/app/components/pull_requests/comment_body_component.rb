# typed: true
# frozen_string_literal: true

module PullRequests
  class CommentBodyComponent < ApplicationComponent
    attr_reader :comment, :body_html, :classes

    PLACEHOLDER_MESSAGE = GitHub::HTMLSafeString.make("No description provided.")

    renders_one :actions

    def initialize(comment:, body_html:, classes: "d-block")
      @comment = comment
      @body_html = body_html
      @classes = classes
    end

    def body_classes
      class_names(
        "comment-body markdown-body js-comment-body soft-wrap css-overflow-wrap-anywhere",
        # Containing the text selection to the boundaries of this element; see https://developer.mozilla.org/en-US/docs/Web/CSS/user-select %>
        "user-select-contain",
        classes,
        "email-format" => comment.created_via_email
      )
    end
  end
end
