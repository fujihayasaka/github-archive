# typed: true
# frozen_string_literal: true

module FeedPosts
  class CommentsComponent < ApplicationComponent
    attr_reader :comments, :reaction_context, :parent, :page

    SHOW_MORE_COUNT = 2

    # comments - A list of FeedPostComment
    # reaction_context - An instance of FeedPost::CommentReactionContext
    def initialize(comments:, reaction_context:, page: 1)
      @comments = comments
      @reaction_context = reaction_context
      @page = page
    end

    def feed_post
      comments.first&.feed_post
    end

    def visible_comments
      @comments.last(SHOW_MORE_COUNT * page)
    end

    def previous_comments?
      @comments.length - (page * SHOW_MORE_COUNT) > 0
    end

    def previous_comments_count
      @comments.length - (page * SHOW_MORE_COUNT)
    end

    def show_previous_replies_text
      units = pluralize(previous_comments_count, "previous reply")
      "Show #{units}"
    end

  end
end
