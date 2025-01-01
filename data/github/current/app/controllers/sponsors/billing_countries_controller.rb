# typed: strict
# frozen_string_literal: true

class Sponsors::BillingCountriesController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations

  before_action :require_acceptance_into_sponsors_program

  layout "layouts/sponsors"

  stylesheet_bundle :sponsors

  sig { void }
  def update
    sponsors_listing = T.must_because(sponsorable_sponsors_listing) do
      "required by `require_acceptance_into_sponsors_program` filter"
    end

    if active_stripe_account
      flash[:error] = "You must set your billing country or region in the Stripe dashboard"
    else
      sponsors_listing.billing_country_validation_enabled = true

      if sponsors_listing.update(billing_country: params[:billing_country])
        new_value = sponsors_listing.billing_country
        flash[:notice] = "Updated billing country or region to #{new_value}"
      else
        errors = sponsors_listing.errors.full_messages
        flash[:error] = "Failed to set billing country or region: #{errors.to_sentence}"
      end
    end

    redirect_to sponsorable_dashboard_settings_path(sponsorable)
  end

  sig { returns(T.any(Symbol, GitHubSponsors::Types::Sponsorable)) }
  private def target_for_conditional_access
    target_sponsorable = sponsorable
    return :no_target_for_conditional_access unless target_sponsorable # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    target_sponsorable
  end
end
