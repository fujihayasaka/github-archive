# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Waitlist::ExportsController < StafftoolsController
  def create
    filter = if params[:filter].present?
      params[:filter].split(",").map(&:to_sym)
    else
      :all
    end
    report = SponsorsListing::Export.new(filter: filter)
    send_data(report.as_csv, type: "text/csv", filename: report.filename)
  end
end
