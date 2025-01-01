# typed: true
# frozen_string_literal: true

class Marketplace::Listings::TransparencyReportExportsController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  before_action :marketplace_required

  def create
    report = Marketplace::Listings::TransparencyReport.new(listing: listing).as_csv
    send_data(report, type: "text/csv")
  end

  private

  memoize def listing
    Marketplace::Listing.find_by!(slug: params[:listing_slug])
  end

  def resource_for_conditional_access
    listing
  end
end
