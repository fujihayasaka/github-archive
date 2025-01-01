# typed: true
# frozen_string_literal: true

module Discussions
  class UnminimizedDiscussionOrCommentComponent < ApplicationComponent
    # discussion_or_comment - a Discussion or DiscussionComment
    # timeline - a DiscussionTimeline for the specified discussion or the specified comment's discussion
    # comment_is_nested - Boolean indicating whether the specified comment is a reply to another comment; only
    #                     applicable when `discussion_or_comment` is a DiscussionComment
    # has_paginated_nested_comments - Boolean indicating whether the specified comment has more replies than we want
    #                                 to show in a single page, only applicable when `discussion_or_comment` is a
    #                                 DiscussionComment
    # page - Integer indicating which page of nested replies to show
    def initialize(discussion_or_comment:, timeline:, comment_is_nested: false, has_paginated_nested_comments: false, page: nil, anchor_id: nil, back_page: nil, forward_page: nil)
      @discussion_or_comment = discussion_or_comment
      @timeline = timeline
      @comment_is_nested = !!comment_is_nested
      @has_paginated_nested_comments = !!has_paginated_nested_comments
      @page = page || 1
      @anchor_id = anchor_id
      @back_page = back_page || 0
      @forward_page = forward_page || 0
    end

    private

    attr_reader :discussion_or_comment, :timeline, :page, :back_page, :forward_page

    def render?
      discussion_or_comment.present? && timeline.present?
    end

    def comment_is_nested?
      @comment_is_nested
    end

    def has_paginated_nested_comments?
      @has_paginated_nested_comments
    end

    memoize def viewer_did_author?
      logged_in? && discussion_or_comment.author == current_user
    end

    memoize def show_child_comments_container?
      discussion_or_comment.is_a?(DiscussionComment) && discussion_or_comment.top_level_comment?
    end

    memoize def show_answer?
      timeline.show_discussion_mark_answer?(discussion_or_comment)
    end

    memoize def anchor_id
      if @anchor_id.nil? && show_child_comments_container?
        first_child_comment = timeline.child_comments(discussion_or_comment).first
        first_child_comment&.id
      else
        @anchor_id
      end
    end

    def form_path
      if discussion_or_comment.is_a?(DiscussionComment)
        discussion_comment_path(timeline.repo_owner_login, timeline.repo_name, timeline.discussion_number,
          discussion_or_comment)
      else
        discussion_path(timeline.discussion_number, timeline.repository)
      end
    end

    def show_poll_edit?
      discussion_or_comment.is_a?(Discussion) && discussion_or_comment.category.supports_polls?
    end

    def container_tag
      show_answer? && discussion_or_comment.answer? ? :section : :div
    end

    def container_aria_attrs
      show_answer? && discussion_or_comment.answer? ? { label: "Marked as Answer" } : {}
    end
  end
end
