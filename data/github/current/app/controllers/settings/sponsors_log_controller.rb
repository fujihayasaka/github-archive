# typed: true
# frozen_string_literal: true

class Settings::SponsorsLogController < ApplicationController
  include Settings::ControllerMethods

  before_action :sponsors_required
  before_action :login_required

  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:index]

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  PER_PAGE = 20

  def index
    period = params[:period].presence&.to_sym || SponsorsActivity::DEFAULT_PERIOD
    activities = SponsorsActivity
      .for_period(period)
      .for_sponsor(current_user)
      .with_sponsor_action
      .by_timestamp
      .paginate(page: current_page, per_page: PER_PAGE)
    total_pages = activities.total_pages
    SponsorsActivity.preload_for_activity_component(activities)
    total_in_page = activities.size
    render "settings/sponsors_log/index", locals: {
      period: period,
      activities: activities,
      total_in_page: total_in_page,
      total_pages: total_pages,
    }
  end
end
