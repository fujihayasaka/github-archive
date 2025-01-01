# typed: true
# frozen_string_literal: true

class FeedPosts::TagsMenuController < ApplicationController
  include UsersHelper

  before_action :require_xhr
  before_action :require_topic_feeds_enabled?
  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations

  def index
    render partial: "feed_posts/tags_menu", locals: {
      pinned_topics: current_user.starred_topics.limit(User::PinnedFeedsDependency::MAX_STARRED_TOPICS),
      for_you_context: for_you_context,
    }
  end

  private

  def for_you_context
    params[:context].nil?
  end

  def label_hydro_data(topic_id:)
    helpers.feed_clicks_hydro_attrs(click_target: "feed_post_tag", metadata: {
      clicked_resource_type: Conduit::AnalyticsHelper::ResourceType::TOPIC,
      clicked_resource_id: topic_id
    })
  end
  helper_method :label_hydro_data

  def require_topic_feeds_enabled?
    render_404 unless user_or_global_feature_enabled?(:feeds_v2)
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
