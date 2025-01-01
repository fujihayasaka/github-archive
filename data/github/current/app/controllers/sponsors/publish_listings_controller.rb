# typed: strict
# frozen_string_literal: true

class Sponsors::PublishListingsController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations

  before_action :non_waitlisted_sponsors_listing_required
  before_action :require_acceptance_into_sponsors_program, only: :create

  sig { void }
  def create
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end

    if listing.can_publish?
      listing.publish!
    elsif listing.can_request_approval?
      listing.request_approval!
      flash[:notice] = "Your profile requires additional review. You'll get an email "\
        "from us when your profile has been approved."
    else
      flash[:error] = "Your profile cannot be submitted for approval at this time."
    end

    redirect_to sponsorable_dashboard_path(sponsorable)
  end

  private

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
