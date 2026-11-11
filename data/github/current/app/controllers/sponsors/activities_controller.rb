# typed: true
# frozen_string_literal: true

class Sponsors::ActivitiesController < ApplicationController
  include Sponsors::AdminableControllerValidations

  before_action :require_acceptance_into_sponsors_program
  before_action :non_waitlisted_sponsors_listing_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  PER_PAGE = 50

  stylesheet_bundle :sponsors

  def index
    period = params[:period].presence&.to_sym || SponsorsActivity::DEFAULT_PERIOD
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#require_acceptance_into_sponsors_program checks for nil"
    end

    if request.xhr?
      activities = listing.activities.with_sponsorable_action.for_period(period).by_timestamp
      render Sponsors::Activities::TimelineComponent.new(
        activities: activities,
        page: current_page,
        per_page: PER_PAGE,
        activities_path: sponsorable_dashboard_activities_path(sponsorable, period: period),
      ), layout: false
    else
      render "sponsors/activities/index", locals: {
        sponsorable: sponsorable,
        sponsors_listing: listing,
        period: period,
        page: current_page,
        per_page: PER_PAGE,
      }
    end
  end

  private

  def target_for_conditional_access
    return :no_target_for_conditional_access unless sponsorable # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    sponsorable
  end
end
