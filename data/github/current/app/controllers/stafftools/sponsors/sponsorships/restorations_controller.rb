# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Sponsorships::RestorationsController < StafftoolsController
  before_action :require_sponsorship

  def create
    RestoreSponsorshipsJob.perform_later(sponsor: sponsor, sponsorships: [sponsorship], actor: current_user)
    flash[:notice] = "Enqueued restoration of sponsorship to #{sponsorship.sponsorable_login}"
    redirect_to billing_stafftools_user_path(sponsor)
  end

  private

  def require_sponsorship
    render_404 unless sponsorship.present?
  end

  def sponsorship
    Sponsorship.find_by(id: params[:sponsorship_id])
  end

  def sponsor
    sponsorship.sponsor
  end
end
