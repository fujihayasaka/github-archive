# typed: strict
# frozen_string_literal: true

class Sponsors::ReactivatesController < ApplicationController
  include Sponsors::AdminableControllerValidations

  before_action :non_waitlisted_sponsors_listing_required
  before_action :non_banned_sponsors_listing_required
  skip_before_action :enabled_sponsors_listing_required

  sig { void }
  def create
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    if listing.can_reactivate?
      listing.reactivate!
      flash[:notice] = "Okay, your GitHub Sponsors account has been reactivated."
    else
      flash[:error] = "You cannot reactivate your GitHub Sponsors account at this time. " \
        "Please contact support to be added to GitHub Sponsors."
    end

    redirect_to sponsorable_dashboard_path(sponsorable)
  end

  private

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
