# typed: true
# frozen_string_literal: true

class Orgs::SponsorsLogController < Orgs::Controller
  before_action :sponsors_required
  before_action :login_required
  before_action :require_billing_manageable

  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:index]

  PER_PAGE = 20

  def index
    period = params[:period].presence&.to_sym || SponsorsActivity::DEFAULT_PERIOD
    sponsor_ids = [this_organization.id, this_organization.sponsoring_linked_organization_id].compact
    activities = SponsorsActivity
      .for_period(period)
      .for_sponsor(sponsor_ids)
      .with_sponsor_action
      .by_timestamp
      .paginate(page: current_page, per_page: PER_PAGE)
    total_pages = activities.total_pages
    SponsorsActivity.preload_for_activity_component(activities)
    total_in_page = activities.size
    render "orgs/sponsors_log/index", locals: {
      period: period,
      activities: activities,
      total_in_page: total_in_page,
      total_pages: total_pages,
    }
  end

  private

  def require_billing_manageable
    render_404 unless org_billing_manageable?(this_organization)
  end
end
