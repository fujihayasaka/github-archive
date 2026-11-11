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
  global_navigation_title "Feed", only: [:show]

  def show
    return redirect_to "/" unless helpers.dashboard_universe_enabled?
    return redirect_to "/" if FeatureFlag.vexi.enabled?(:disable_dashboard_feed_page, current_user, default: false)

    render "dashboard/feed/show", layout: "layouts/dashboard_three_column", locals: {
      query: params[:q],
      feed_title: "Feed",
    }
  end

  private

  def resource_for_conditional_access
    # current_user is undefined if the user is not logged in and the resource must be defined
    # login is required before this action so this is safe
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess

    current_user
  end
end
