# typed: true
# frozen_string_literal: true

class MarketplaceListingTransactionsController < ApplicationController

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace

  before_action :render_404, unless: :logged_in?
  before_action :marketplace_required
  # only non-graphql actions need to check for presence of this_marketplace_listing
  # this list should be updated as more views are converted
  before_action :this_marketplace_listing_required, only: :index

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  USERS_PAGE_SIZE = 20

  def index
    return render_404 unless this_marketplace_listing.can_viewer_read_insights?(current_user)
    @query = params.fetch(:q, "")

    report = Marketplace::ListingTransactionsReport.new \
      listing_id:   this_marketplace_listing.id,
      listing_slug: this_marketplace_listing.slug,
      period:       params[:period],
      user:         current_user,
      sort_type:    params[:sort],
      plan_type:    params[:plan],
      user_name:    @query

    @transactions = report.send(:fetch_transactions).paginate(page: current_page, per_page: USERS_PAGE_SIZE)
    @listing_plan_types = Marketplace::ListingPlan.where(marketplace_listing_id: this_marketplace_listing.id)

    adjusted_plan_name = params[:plan] ? Marketplace::ListingPlan.find(params[:plan].to_i).name : "All plans"

    respond_to do |format|
      format.html do
        render "marketplace_listing_transactions/index", locals: {
          adjusted_plan_name: adjusted_plan_name,
          current_user: current_user,
          transactions: @transactions,
          report: report,
          plan_type: params[:plan],
          listing_name: this_marketplace_listing.name,
          listing_slug: this_marketplace_listing.slug,
          marketplace_listing: this_marketplace_listing,
          listing_plan_types: @listing_plan_types,
          user_name: @query
        }
      end

      format.csv do
        response.headers["Content-Type"] = "text/csv"

        send_data \
          report.truncate(false).as_csv,
          type:     "text/csv",
          filename: report.filename
      end
    end
  end

  private

  memoize def this_marketplace_listing
    Marketplace::Listing.find_by(slug: params[:listing_slug])
  end

  def this_marketplace_listing_required
    render_404 unless this_marketplace_listing
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_marketplace_listing # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_marketplace_listing.owner
  end
end
