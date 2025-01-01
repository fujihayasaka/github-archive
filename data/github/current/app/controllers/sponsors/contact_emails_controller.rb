# typed: strict
# frozen_string_literal: true

class Sponsors::ContactEmailsController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations

  before_action :at_least_waitlisted_listing_required

  layout "layouts/sponsors"

  stylesheet_bundle :sponsors

  sig { void }
  def update
    sponsors_listing = T.must_because(sponsorable_sponsors_listing) do
      "required by `at_least_waitlisted_listing_required` filter"
    end

    new_email_id = params[:contact_email_id] ? params[:contact_email_id].to_i : nil
    sponsors_listing.contact_email_id = new_email_id

    if sponsors_listing.save
      contact_email = T.must_because(sponsors_listing.contact_email) { "record is created as part of this action" }
      flash[:notice] = "Updated contact email to #{contact_email.email}"
    else
      errors = sponsors_listing.errors.full_messages
      flash[:error] = "Failed to set contact email: #{errors.to_sentence}"
    end

    if sponsors_listing.accepted_into_sponsors?
      redirect_to sponsorable_dashboard_settings_path(sponsorable)
    else
      redirect_to sponsorable_signup_path(sponsorable)
    end
  end

  private

  sig { void }
  def at_least_waitlisted_listing_required
    return if sponsorable_sponsors_listing
    render_404
  end

  sig { returns(GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    T.must_because(sponsorable) { "required by `sponsorable_required` filter" }
  end
end
