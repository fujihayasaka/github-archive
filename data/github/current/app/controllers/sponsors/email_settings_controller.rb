# typed: true
# frozen_string_literal: true

class Sponsors::EmailSettingsController < ApplicationController
  include Sponsors::AdminableControllerValidations

  before_action :non_waitlisted_sponsors_listing_required
  before_action :require_acceptance_into_sponsors_program

  layout "layouts/sponsors"

  stylesheet_bundle :sponsors

  def update
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#require_acceptance_into_sponsors_program filters out nil listing"
    end
    listing.update_email_opt_outs(updated_email_settings)

    if listing.save
      flash[:notice] = "Updated email preferences"
    else
      errors = listing.errors.full_messages
      flash[:error] = "Failed to update email preferences: #{errors.to_sentence}"
    end

    redirect_to sponsorable_dashboard_settings_path(sponsorable)
  end

  private

  def updated_email_settings
    updated_settings = SponsorsEmailOptOuts.new(bitmask: nil)

    if params[:opt_out_of_all]
      updated_settings.opt_out_of(:all)
      return updated_settings
    end

    receive_email_params = [
      :new_sponsorships, :cancelled_sponsorships, :upgrade_notices,
      :goal_completed, :milestone_reached, :reached_match_cap
    ]

    receive_email_params.each do |email_param|
      updated_settings.opt_out_of(email_param) unless params[email_param]
    end

    updated_settings
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless sponsorable # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    sponsorable
  end
end
