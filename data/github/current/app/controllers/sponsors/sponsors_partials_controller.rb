# typed: true
# frozen_string_literal: true

class Sponsors::SponsorsPartialsController < ApplicationController
  include Sponsors::SharedControllerMethods

  SPONSORSHIP_PAGINATION_FILTERS = %w[all active inactive].freeze

  before_action :sponsorable_required
  before_action :non_waitlisted_sponsors_listing_required
  before_action :verify_visible_to_viewer
  before_action :non_spammy_user_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    only: [:show]

  def show
    render partial: "sponsors/sponsors_partials/show", locals: {
      sponsorable: sponsorable,
      sponsorships: sponsorships_for_filter,
      next_page_filter: params[:filter],
    }
  end

  private

  def sponsorships_for_filter
    case params[:filter]
    when "active"
      active_sponsorships_for_sponsors_listing
    when "inactive"
      inactive_sponsorships_for_sponsors_listing
    else
      sponsorships_for_sponsors_listing
    end
  end

  def target_for_conditional_access
    sponsorable
  end
end
