# typed: true
# frozen_string_literal: true

class FeedPostsController < ApplicationController
  include GitHub::Memoizer

  before_action :login_required
  before_action :require_feed_enabled
  before_action :require_feature_enabled
  before_action :set_spamurai_form_signals, only: [:create]
  before_action :actor_can_destroy?, only: [:destroy]

  def create
    if post = FeedPost.create_with_references(create_params)
      success = true
      Conduit::KVBackedCache.invalidate_for(current_user)

      render partial: "feed_posts/create", locals: {
        item: Conduit::FeedItem.build(
          post.to_twirp_feed_item,
          actor: current_user,
          subject: post,
        )
      }
    else
      success = false
      render plain: "Failed to create feed post", status: 500
    end
  ensure
    GitHub.dogstats.increment("feed_post.create", tags: ["success:#{success}"])
  end

  def destroy
    if feed_post.destroy
      success = true
      flash[:notice] = "Post deleted"
    else
      success = false
      flash[:error] = "Couldn't delete post"
    end

    redirect_to :back
  ensure
    GitHub.dogstats.increment("feed_post.destroy", tags: ["success:#{success}"])
  end

  private

  memoize def feed_post
    FeedPost.find(params[:id])
  end

  def create_params
    params.require(:feed_post).permit(:body, :author_id, :owner_id, :topic_id)
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

  def actor_can_destroy?
    head 403 unless feed_post.deletable_by?(current_user)
  end

  def set_spamurai_form_signals
    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)
  end
end
