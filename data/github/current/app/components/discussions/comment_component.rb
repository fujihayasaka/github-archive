# typed: true
# frozen_string_literal: true

module Discussions
  class CommentComponent < ApplicationComponent
    # comment - a Discussion or DiscussionComment
    # timeline - a DiscussionTimeline
    def initialize(
      comment:,
      error_message: nil,
      page: 1,
      show_all_nested_comments: false,
      subscribe_to_live_updates: false,
      timeline:,
      anchor_id: nil,
      back_page: 0,
      forward_page: 0,
      hpc: false
    )
      @comment = comment
      @error_message = error_message
      @page = page
      @show_all_nested_comments = show_all_nested_comments
      @subscribe_to_live_updates = subscribe_to_live_updates
      @timeline = timeline
      @anchor_id = anchor_id
      @back_page = back_page
      @forward_page = forward_page
      @hpc = hpc
    end

    private

    attr_reader :comment, :error_message, :page, :timeline, :anchor_id, :back_page, :forward_page, :hpc

    def minimized?
      # comment could be a Discussion
      comment.try(:minimized?)
    end

    def show_all_nested_comments?
      @show_all_nested_comments
    end

    def subscribe_to_live_updates?
      @subscribe_to_live_updates || (comment? && show_all_nested_comments?)
    end

    def has_paginated_nested_comments?
      return false unless comment?

      # This make this method name a bit of a misnomer, as it'll return true even if you still have
      # *previous* nested comments to expand. Investigate renaming it if/when the feature flag is
      # shipped.
      timeline.total_next_child_comments_count(comment) > 0
    end

    def comment?
      comment.is_a?(DiscussionComment)
    end
  end
end
