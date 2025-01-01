# typed: true
# frozen_string_literal: true

class Dashboard::PinnedTopicsController < ApplicationController
  include UsersHelper

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
  ApplicationRecord::Configurations,

  def index
    render partial: "dashboard/pinned_topics", locals: {
      pinned_topics: current_user.pinned_topics,
      active_label: params[:active] || "for-you",
      expanded: params[:expanded] == "true"
    }
  end

  private

  def require_topic_feeds_enabled?
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
end
