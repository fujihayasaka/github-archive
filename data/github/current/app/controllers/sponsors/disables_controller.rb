# typed: strict
# frozen_string_literal: true

class Sponsors::DisablesController < ApplicationController
  include Sponsors::AdminableControllerValidations

  before_action :non_waitlisted_sponsors_listing_required
  before_action :require_acceptance_into_sponsors_program

  sig { void }
  def create
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    if listing.allow_self_service_disable?
      listing.actor = current_user
      listing.disable!
      listing.deactivate_all_stripe_accounts
      flash[:notice] = "Okay, your GitHub Sponsors account has been disabled."
    else
      flash[:error] = "You cannot disable your GitHub Sponsors account at this time. " \
        "Please contact support to be removed from GitHub Sponsors."
    end

    redirect_to sponsorable_dashboard_path(sponsorable)
  end

  private

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
