# typed: true
# frozen_string_literal: true

class Dashboard::FavoritesPinnableItemsController < ApplicationController
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
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
    only: [:show]

  ITEMS_PER_PAGE = 40

  def show
    respond_to do |format|
      format.html do
        render(
          partial: "dashboard/favorites_modal/pinnable_items",
          locals: {
            pinnable_items: pinnable_items,
            pinned_items: current_page > 1 ? [] : authorized_pinned_items,
            pinned_items_remaining: current_user.dashboard_pinned_items_remaining,
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
