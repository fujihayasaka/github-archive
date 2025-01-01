# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::ActivitiesController < Stafftools::SponsorsController
  layout "application"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  PER_PAGE = 10

  def index
    respond_to do |format|
      format.html do
        if request.xhr?
          render partial: "stafftools/sponsors/members/activities/sponsors_activities", locals: {
            activities: sponsors_activities,
            tiers: tiers,
            sponsorable_login: this_listing.sponsorable_login
          }
        else
          render "stafftools/sponsors/members/activities/index", locals: {
            activities: sponsors_activities,
            tiers: tiers,
            sponsorable_login: this_listing.sponsorable_login,
            sponsors_listing: this_listing
          }
        end
      end
    end
  end

  private

  memoize def sponsors_activities
    this_sponsorable
      .sponsors_activities
      .with_sponsorable_action
      .filter_by_user_handle(allowed_params[:handle])
      .filter_by_sponsors_action(allowed_params[:sponsor_action])
      .filter_by_current_tier(allowed_params[:current_tier])
      .filter_by_old_tier(allowed_params[:old_tier])
      .filter_by_date(allowed_params[:date])
      .by_timestamp
      .paginate(page: current_page, per_page: PER_PAGE)
  end

  memoize def tiers
    this_listing.sponsors_tiers
  end

  def allowed_params
    params.permit(:member_id, :page, :handle, :sponsor_action, :current_tier, :old_tier, :date)
  end
end
