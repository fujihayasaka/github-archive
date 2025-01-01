# typed: strict
# frozen_string_literal: true

class Sponsors::CustomTierSettingsController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations

  before_action :require_acceptance_into_sponsors_program
  before_action :non_waitlisted_sponsors_listing_required

  sig { void }
  def update
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#require_acceptance_into_sponsors_program ensures non-nil"
    end
    old_amount = listing.suggested_custom_tier_amount_in_cents

    if params[:suggested_custom_tier_amount]
      if request.xhr?
        return save_and_render_suggested_amount(params[:suggested_custom_tier_amount])
      else
        listing.suggested_custom_tier_amount_in_dollars = params[:suggested_custom_tier_amount]
      end
    end

    if params[:min_custom_tier_amount]
      if request.xhr?
        return save_and_render_minimum_amount(params[:min_custom_tier_amount])
      else
        listing.min_custom_tier_amount_in_dollars = params[:min_custom_tier_amount]
      end
    end

    if listing.save
      listing.instrument_custom_amount_settings_change(old_amount, actor: current_user)
      return head(:ok) if request.xhr?

      flash[:notice] = "Updated your settings for custom sponsorships."
    else
      return head(:unprocessable_entity) if request.xhr?

      error = listing.errors.full_messages.join(", ")
      flash[:error] = "Could not save your settings: #{error}"
    end

    redirect_to sponsorable_dashboard_tiers_path(frequency: frequency_param)
  end

  private

  sig { returns T.any(GitHubSponsors::Types::Sponsorable, Symbol) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { params(amount_in_dollars: String).void }
  def save_and_render_minimum_amount(amount_in_dollars)
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#require_acceptance_into_sponsors_program ensures non-nil"
    end
    listing.min_custom_tier_amount_in_dollars = amount_in_dollars.to_i

    respond_to do |format|
      format.json do
        if amount_in_dollars.to_f % 1 != 0
          error_message = "must be an integer"
        elsif amount_in_dollars.to_f < 0
          error_message = "must be at least $0"
        else
          return head(:ok) if listing.save
          errors = listing.errors[:min_custom_tier_amount_in_cents]
          error_message = errors.to_sentence
        end
        render json: { message: "Minimum custom amount #{error_message}" }, status: :unprocessable_entity
      end
    end
  end

  sig { params(amount_in_dollars: String).void }
  def save_and_render_suggested_amount(amount_in_dollars)
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#require_acceptance_into_sponsors_program ensures non-nil"
    end
    listing.suggested_custom_tier_amount_in_dollars = amount_in_dollars.to_i

    respond_to do |format|
      format.json do
        if amount_in_dollars.to_f % 1 != 0
          error_message = "must be an integer"
        elsif amount_in_dollars.to_f < 0
          error_message = "must be at least $0"
        else
          return head(:ok) if listing.save
          errors = listing.errors[:suggested_custom_tier_amount_in_cents]
          error_message = errors.to_sentence
        end
        render json: { message: "Suggested custom amount #{error_message}" }, status: :unprocessable_entity
      end
    end
  end
end
