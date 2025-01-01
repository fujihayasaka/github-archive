# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::PotentialSponsorableBannerPreviewsController < StafftoolsController
  before_action :sponsors_required
  before_action :require_potential_sponsorable

  def create
    potential_sponsorship = potential_sponsorable.potential_sponsorships_as_sponsorable
      .new(potential_sponsorship_params)
    potential_sponsorship.created_by = current_user
    potential_sponsorship.potential_sponsor = potential_sponsor
    render Sponsors::PotentialSponsorableBannerComponent.new(
      potential_sponsorship: potential_sponsorship,
      preview_mode: true,
    ), layout: false
  end

  private

  memoize def potential_sponsorship_params
    params.require(:potential_sponsorship).permit(:potential_sponsor_id, :message)
  end

  memoize def potential_sponsorable
    User.find_by_login(params[:user_id])
  end

  memoize def potential_sponsor
    if login = params[:potential_sponsor_login]
      User.find_by_login(login)
    elsif id = potential_sponsorship_params[:potential_sponsor_id]
      User.find_by(id: id)
    end
  end

  def require_potential_sponsorable
    render_404 unless potential_sponsorable
  end
end
