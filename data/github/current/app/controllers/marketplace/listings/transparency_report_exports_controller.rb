# typed: true
# frozen_string_literal: true

class Marketplace::Listings::TransparencyReportExportsController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  before_action :marketplace_required
  before_action :listing_is_published_or_edit_required

  def create
    report = Marketplace::Listings::TransparencyReport.new(listing: listing).as_csv
    send_data(report, type: "text/csv")
  end

  private

  def listing_is_published_or_edit_required
    render_404 unless listing.publicly_listed? || listing.allowed_to_edit?(current_user)
  end

  memoize def listing
    Marketplace::Listing.find_by!(slug: params[:listing_slug])
  end

  def resource_for_conditional_access
    listing
  end
end
