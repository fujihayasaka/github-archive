# typed: true
# frozen_string_literal: true

class Dashboard::FavoritesModalController < ApplicationController
  include DashboardSidebarHelper

  before_action :login_required
  before_action :ensure_feature_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  ITEMS_PER_PAGE = 40

  def show
    respond_to do |format|
      format.html do
        render("dashboard/favorites_modal/show",
          layout: false,
          format: [:html],
          locals: {
            pinnable_items: pinnable_items,
            pinned_items: authorized_pinned_items,
            has_pinnable_repos: any_pinnable_repos?,
            pinned_items_remaining: current_user.dashboard_pinned_items_remaining,
            has_pinnable_gists: false,
          }
        )
      end
    end
  end

  private

  def pinnable_items
    params[:q].present? ? fetch_pinnable_repositories(params[:q], items_per_page: ITEMS_PER_PAGE) : fetch_pinnable_items(items_per_page: ITEMS_PER_PAGE)
  end

  def ensure_feature_enabled
    if !user_feature_enabled?(UserDashboardPin::WEB_FEATURE)
      render_404
    end
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
