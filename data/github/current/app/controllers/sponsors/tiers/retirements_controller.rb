# typed: strict
# frozen_string_literal: true

class Sponsors::Tiers::RetirementsController < ApplicationController
  include Sponsors::AdminableControllerValidations

  before_action :require_acceptance_into_sponsors_program
  before_action :non_waitlisted_sponsors_listing_required

  rescue_from Sponsors::RetireSponsorsTier::ForbiddenError, with: :render_404
  rescue_from Sponsors::RetireSponsorsTier::UnprocessableError do |error|
    T.bind(self, Sponsors::Tiers::RetirementsController)
    flash[:error] = error.message
    redirect_to sponsorable_dashboard_tiers_path
  end

  sig { void }
  def create
    Sponsors::RetireSponsorsTier.call(tier: tier, viewer: current_user)

    flash[:notice] = "You retired the #{tier} tier."

    if tier.one_time?
      redirect_to sponsorable_dashboard_tiers_path(frequency: "one-time")
    else
      redirect_to sponsorable_dashboard_tiers_path
    end
  end

  protected

  sig { returns(SponsorsTier) }
  memoize def tier
    sponsors_listing = T.must_because(sponsorable_sponsors_listing) do
      "required by `non_waitlisted_sponsors_listing_required`"
    end
    sponsors_listing.sponsors_tiers.find_by!(id: params[:tier_id])
  end

  private

  sig { returns(T.any(GitHubSponsors::Types::Sponsorable, Symbol)) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
