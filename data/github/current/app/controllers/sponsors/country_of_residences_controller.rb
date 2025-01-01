# typed: strict
# frozen_string_literal: true

class Sponsors::CountryOfResidencesController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations

  before_action :require_acceptance_into_sponsors_program
  before_action :require_non_organization_sponsorable
  before_action :ensure_no_active_stripe_account

  layout "layouts/sponsors"

  stylesheet_bundle :sponsors

  sig { void }
  def update
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#require_acceptance_into_sponsors_program ensures non-nil"
    end
    if listing.update(country_of_residence: params[:country_of_residence])
      new_value = listing.country_of_residence
      flash[:notice] = "Updated country or region of residence to #{new_value}"
    else
      errors = listing.errors.full_messages
      flash[:error] = "Failed to set country: #{errors.to_sentence}"
    end

    redirect_to_dashboard_or_return_to
  end

  private

  sig { void }
  def require_non_organization_sponsorable
    sponsorable = T.must_because(self.sponsorable) { "#sponsorable_required ensures non-nil" }
    render_404 if sponsorable.organization?
  end

  sig { void }
  def ensure_no_active_stripe_account
    if active_stripe_account
      flash[:error] = "Please update your country or region of residence on Stripe instead."
      redirect_to_dashboard_or_return_to
    end
  end

  sig { void }
  def redirect_to_dashboard_or_return_to
    if params[:return_to]
      safe_redirect_to params[:return_to]
    else
      redirect_to sponsorable_dashboard_settings_path(sponsorable)
    end
  end

  sig { returns T.any(GitHubSponsors::Types::Sponsorable, Symbol) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
