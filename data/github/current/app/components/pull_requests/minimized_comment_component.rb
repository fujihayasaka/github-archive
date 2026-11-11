# typed: true
# frozen_string_literal: true

module PullRequests
  class MinimizedCommentComponent < ApplicationComponent
    attr_reader :comment, :path, :details_classes, :summary_classes

    def initialize(comment:, path:, details_classes: nil, summary_classes: nil)
      @comment = comment
      @path = path
      @details_classes = details_classes
      @summary_classes = summary_classes
    end

    def minimized_reason
      if Issue::Adapter::CommentAdapter::MINIMIZE_REASONS.has_key?(comment.minimized_reason&.to_sym)
        Issue::Adapter::CommentAdapter::MINIMIZE_REASONS[comment.minimized_reason&.to_sym]
      else
        comment.minimized_reason
      end
    end

    private

    def can_see_minimized_by_staff_comment
      !logged_in? && !comment.minimized_by_staff? || logged_in? && comment.viewer_can_see?(current_user)
    end
  end
end
