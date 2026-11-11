# typed: true
# frozen_string_literal: true

class Dashboard::FeedController < ApplicationController
  helper InProductTargeting::DashboardRightColumnHelper
  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Ballast,
    ApplicationRecord::Profiles

  javascript_bundle :dashboard

  stylesheet_bundle :dashboard, :discussions

  YOUR_TEAMS_LIMIT = 7

  def show
    return redirect_to "/" unless helpers.dashboard_universe_enabled?
    return redirect_to "/" if FeatureFlag.vexi.enabled?(:disable_dashboard_feed_page, current_user, default: false)

    context_region_title "Feed"

    render "dashboard/feed/show", layout: "layouts/dashboard_three_column", locals: {
      query: params[:q],
      feed_title: "Feed",
      team_query: params[:team],
      teams: helpers.fetch_paginated_teams(per_page: YOUR_TEAMS_LIMIT, current_page_for_teams: current_page_for_teams),
      turbo_src: nil,
    }
  end

  private

  def resource_for_conditional_access
    # current_user is undefined if the user is not logged in and the resource must be defined
    # login is required before this action so this is safe
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess

    current_user
  end

  def current_page_for_teams
    page = params[:your_teams_cursor].to_i
    page == 0 ? 1 : page
  end
end
