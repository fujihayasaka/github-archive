# typed: true
# frozen_string_literal: true

class Dashboard::FavoritesController < ApplicationController
  include DashboardSidebarHelper

  before_action :login_required
  before_action :ensure_feature_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    render "dashboard/favorites/index", locals: {
      authorized_pinned_items: authorized_pinned_items,
      any_pinnable_items: any_pinnable_repos?,
      any_pinned_items: any_pinned_repos?,
      pinned_items_remaining: current_user.dashboard_pinned_items_remaining,
    }, layout: false
  end

  def create
    ids_and_types = params[:pinned_items_id_and_type]
    pinned_items = UserDashboardPinner.get_pinned_items_from_id_and_type(ids_and_types)

    if params[:reorder] && pinned_items.empty?
      return head :not_found
    end

    # This is a hack to ensure we include pinned items that aren't
    # visible because they're hidden behind 2FA/SSO
    pinned_items = unauthorized_pinned_items + pinned_items

    UserDashboardPinner.pin(*pinned_items, user: current_user, viewer: current_user)

    if params[:reorder]
      head :ok
    else
      redirect_to "/"
    end
  end

  private

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
