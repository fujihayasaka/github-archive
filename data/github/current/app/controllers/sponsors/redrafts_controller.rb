# typed: strict
# frozen_string_literal: true

class Sponsors::RedraftsController < ApplicationController
  include Sponsors::AdminableControllerValidations

  before_action :non_waitlisted_sponsors_listing_required

  sig { void }
  def create
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    if listing.can_redraft?
      listing.redraft!
      flash[:notice] = "Okay, this Sponsors profile has been unpublished."
    else
      flash[:error] = "This Sponsors profile cannot be unpublished."
    end

    redirect_to sponsorable_dashboard_path(sponsorable)
  end

  private

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
