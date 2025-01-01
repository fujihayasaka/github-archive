# typed: true
# frozen_string_literal: true

module FeedPosts
  class CommentComponent < ApplicationComponent
    def initialize(comment:, reaction_context:)
      @comment = comment
      @reaction_context = reaction_context
    end

    def render?
      comment.present?
    end

    def user
      comment.user
    end

    def created_at
      comment.created_at
    end

    def body_html
      comment.body_html
    end

    def hydro_data(click_target:)
      {}
    end

    memoize def user_reactions
      comment.prelude_user_logins_by_reaction
    end

    memoize def viewer_reaction_contents
      return [] unless reaction_context

      reaction_context
        .viewer_reaction_contents_by_feed_post_comment_id
        .fetch(comment.id, [])
    end

    memoize def show_report_option?
      GitHub.user_abuse_mitigation_enabled? &&
        !viewer_is_author &&
        user.present?
    end

    private

    def viewer_is_author
      current_user.id == user.id
    end

    attr_reader :comment, :reaction_context
  end
end
