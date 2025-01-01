# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::CriterionController < Stafftools::SponsorsController
  before_action :criterion_required

  def update
    if this_criterion.sponsors_criterion.automated?
      render json: { error: "Automated criteria cannot be updated manually" },
        status: :unprocessable_entity
      return
    end

    this_criterion.met = params[:is_met] == "1"
    this_criterion.reviewer = current_user if this_criterion.changed?

    if this_criterion.save
      render json: {
        sponsorsMembershipsCriterionId: this_criterion.id,
        isMet: this_criterion.met?,
      }
    else
      render json: { errors: this_criterion.errors },
        status: :unprocessable_entity
    end
  end

  private

  memoize def this_criterion
    SponsorsMembershipsCriterion.where(sponsors_listing_id: this_listing).find_by(id: params[:id])
  end

  def criterion_required
    render_404 unless this_criterion.present?
  end
end
