# typed: true
# frozen_string_literal: true

module Discussions
  class MinimizedCommentComponent < ApplicationComponent
    # comment - a DiscussionComment
    # timeline - a DiscussionTimeline
    def initialize(comment:, timeline:, anchor_id: nil, back_page: 0, forward_page: 0)
      @comment = comment
      @timeline = timeline
      @back_page = back_page || 0
      @forward_page = forward_page || 0
      @anchor_id = anchor_id
    end

    private

    attr_reader :comment, :timeline, :back_page, :forward_page, :anchor_id

    def render?
      comment.present? && timeline.present?
    end

    def show_child_comments_thread?
      comment.is_a?(DiscussionComment) && comment.top_level_comment?
    end

    def can_see_minimized_by_staff_comment
      !logged_in? && !comment.minimized_by_staff? || logged_in? && comment.viewer_can_see?(current_user)
    end
  end
end
