# typed: true
# frozen_string_literal: true

module FeedPosts
  class CommentsController < ApplicationController
    include GitHub::Memoizer

    before_action :login_required
    before_action :require_feed_enabled
    before_action :require_feature_enabled
    before_action :set_spamurai_form_signals, only: [:create]

    def index
      all_comments = feed_post.reload.comments
      render(
        FeedPosts::CommentsComponent.new(
          comments: all_comments,
          reaction_context: ::FeedPost::CommentReactionContext.new(
            comment_ids: all_comments.pluck(:id),
            viewer: current_user
          ),
          page: page,
        ),
        layout: false
      )
    end

    def create
      comment = feed_post.comments.new(
        user: current_user,
        **create_params,
      )

      if comment.save
        all_comments = feed_post.reload.comments
        render json: {
          updateContent: {
            "#post-#{feed_post.id} [data-comments]" =>
              render_to_string(
                FeedPosts::CommentsComponent.new(
                  comments: all_comments,
                  reaction_context: ::FeedPost::CommentReactionContext.new(
                    comment_ids: all_comments.pluck(:id),
                    viewer: current_user
                  ),
                  page: page,
                ),
              ),
          }
        }
      end
    end

    def destroy

    end

    private

    memoize def feed_post
      FeedPost.find(params[:feed_post_id].to_i)
    end

    def create_params
      params.require(:comment).permit(:body)
    end

    def page
      params[:page].to_i
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      current_user
    end

    def require_feed_enabled
      render_404 unless GitHub.conduit_feed_enabled?
    end

    def require_feature_enabled
      render_404 unless user_feature_enabled?(:feed_posts)
    end

    def set_spamurai_form_signals
      GitHub.context.push(spamurai_form_signals: spamurai_form_signals)
    end
  end
end
