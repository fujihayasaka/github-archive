# typed: true
# frozen_string_literal: true

module Comments
  class CommentComponent < ApplicationComponent
    include CommentsHelper

    renders_one :header
    renders_one :body
    renders_one :reactions
    renders_one :edit_form
    renders_one :minimized_comment

    attr_reader :comment, :classes, :id

    def initialize(comment:, classes: "", id: nil)
      @comment = comment
      @classes = classes
      @id = id || comment_dom_id(comment)
    end

    def comment_classes
      class_names(
        "timeline-comment-group js-minimizable-comment-group js-targetable-element my-0 comment previewable-edit js-task-list-container js-comment",
        classes,
        "current-user" => comment.user_id == current_user&.id,
        "unminimized-comment" => !minimized?,
        "minimized-comment" => minimized?,
      )
    end

    def minimized?
      @comment.minimized?
    end
  end
end
