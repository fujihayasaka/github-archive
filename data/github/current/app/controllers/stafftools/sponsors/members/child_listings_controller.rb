# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::ChildListingsController < Stafftools::SponsorsController
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

  PER_PAGE = 5

  def index
    respond_to do |format|
      format.html do
        if request.xhr?
          render partial: "stafftools/sponsors/members/child_listings/child_listings", locals: {
            child_listings: child_listings,
            sponsors_listing: this_listing
          }
        else
          render "stafftools/sponsors/members/child_listings/index", locals: {
            child_listings: child_listings,
            sponsors_listing: this_listing
          }
        end
      end
    end
  end

  private

  memoize def child_listings
    if this_listing.fiscal_host?
      this_listing
        .child_listings
        .matches_sponsorable_login(allowed_params[:handle])
        .filter_by_state(allowed_params[:state])
        .oldest_join_date_first
        .includes(sponsorable: :profile)
        .paginate(page: current_page, per_page: PER_PAGE)
    else
      []
    end
  end

  def allowed_params
    params.permit(:id, :member_id, :page, :handle, :state)
  end
end
