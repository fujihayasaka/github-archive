# frozen_string_literal: true

class CVEsController < InboxController
  include HasPagination

  def index
    year = params[:year]
    page = normalize_page(params[:page])
    cves = CVE.by_year(year).includes(:cve_review).order(:cve_id).paginate(page: page)

    render(CVEs::IndexComponent.new(cves: cves, year: year))
  end

  def create
    ReserveCVEJob.perform_now(force: true)

    redirect_to(cves_path, notice: "A request to reserve CVEs has been made. Wait a moment, then refresh this page to see the newly allocated CVEs.")
  end
end
