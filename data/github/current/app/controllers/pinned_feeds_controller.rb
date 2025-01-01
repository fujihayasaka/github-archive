# typed: true
# frozen_string_literal: true

class PinnedFeedsController < ApplicationController
  include GitHub::Memoizer

  before_action :login_required
  before_action :require_feature_enabled
  before_action :require_user_is_actor
  before_action :require_topic_exists, only: [:create]
  before_action :require_pinned_feed, only: [:destroy]

  def create
    if current_user.pin_feed(topic)
      flash[:notice] = "#{topic.name} feed has been pinned"
    else
      flash[:error] = "#{topic.name} could not be pinned"
    end

    redirect_to dashboard_path
  end

  def destroy
    topic = pinned_feed.topic

    if current_user.unpin_feed(pinned_feed)
      flash[:notice] = "#{topic.name} feed has been unpinned"
    else
      flash[:error] = "#{topic.name} could not be unpinned"
    end

    redirect_to dashboard_path
  end

  private

  def require_topic_exists
    render_404 if topic.nil?
  end

  def require_user_is_actor
    if user_id != current_user.id
      render_404
    end
  end

  def require_pinned_feed
    render_404 if pinned_feed.nil?
  end

  memoize def pinned_feed
    return unless feed_id = params[:pinned_feed_id].presence
    current_user.pinned_feeds.find(feed_id.to_i)
  end

  memoize def topic
    return unless topic_id = params[:topic_id].presence
    Topic.find(topic_id.to_i)
  end

  def user_id
    return unless user_id = params[:user_id].presence
    user_id.to_i
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def require_feature_enabled
    render_404 unless user_feature_enabled?(:pinned_feeds)
  end
end
