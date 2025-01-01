# typed: true
# frozen_string_literal: true

class Dashboard::TopicFeedsSearchController < ApplicationController
  include UsersHelper

  POPULAR_TOPICS = 5
  FEATURED_TOPICS = 2

  before_action :require_feature_enabled
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

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  def index
    render "dashboard/topic_feeds_search/index", layout: false
  end

  def show
    if query
      render "dashboard/topic_feeds_search/search", layout: false, locals: {
        topics: search_query_topics(query),
        query: query,
      }
    else
      render "dashboard/topic_feeds_search/overview", layout: false, locals: {
        starred_topics: starred_topics,
        suggested_topics: suggested_topics,
        popular_topics: popular_topics,
      }
    end
  end

  private

  def query
    params[:q].presence
  end

  def search_query_topics(query)
    if user_or_global_feature_enabled?(:topic_feeds_v2)
      return Topic
              .not_flagged
              .with_name_like(query)
              .order("stargazer_count DESC")
              .limit(10)
    end

    Topic
      .where(id: TopicFeeds::SuggestedTopics::PRESET_TOPIC_IDS)
      .not_flagged
      .with_name_like(query)
      .order("stargazer_count DESC")
      .limit(10)
  end

  def require_feature_enabled
    render_404 unless user_or_global_feature_enabled?(:topic_feeds)
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def suggested_topics
    # we're grabbing the remaining supported topics that haven't been already starred
    suggested_topic_ids = TopicFeeds::SuggestedTopics::PRESET_TOPIC_IDS - user_starred_topic_ids
    Topic.where(id: suggested_topic_ids)
  end

  memoize def user_starred_topic_ids
    current_user.starred_topic_ids
  end

  memoize def starred_topics
    starred_topic_ids = user_starred_topic_ids
    if !user_or_global_feature_enabled?(:topic_feeds_v2)
      # we're grabbing only the starred topics we're supporting for staff ship
      starred_topic_ids = starred_topic_ids.intersection(TopicFeeds::SuggestedTopics::PRESET_TOPIC_IDS)
    end

    Topic.where(id: starred_topic_ids).first(User::PinnedFeedsDependency::MAX_STARRED_TOPICS)
  end

  def popular_topics
    return [] unless user_or_global_feature_enabled?(:topic_feeds_v2)

    Topic
      .not_flagged
      .excluding(starred_topics)
      .popular_on_public_repositories(POPULAR_TOPICS)
  end
end
