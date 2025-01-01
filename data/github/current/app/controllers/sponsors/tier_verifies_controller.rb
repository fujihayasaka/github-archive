# typed: strict
# frozen_string_literal: true

# not named the more sensible `TierPricingChecksController` because some people
# who write adblockers think that all URLs with `pricing` should be blocked
# (which is very silly) and also a `check` means `money` in en_US so that way
# lies sadness too.
class Sponsors::TierVerifiesController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations

  before_action :require_acceptance_into_sponsors_program
  before_action :non_waitlisted_sponsors_listing_required
  skip_before_action :sponsorable_owned_by_current_user_required_for_non_get_requests,
    only: :create

  sig { void  }
  def create
    respond_to do |format|
      format.html_fragment do
        # make sure that the value is not a decimal
        if price_in_cents % 100 != 0
          error_message = "must be an integer"
        elsif !price_in_cents.positive?
          error_message = "must be at least $1"
        else
          tier.valid? # call the validations
          errors = tier.errors[:monthly_price_in_cents]
          return head :ok unless errors.any?
          error_message = errors.to_sentence
        end

        render body: "Tier pricing #{error_message}",
               status: :unprocessable_entity,
               content_type: "text/fragment+html"
      end
    end
  end

  private

  sig { returns(T.any(GitHubSponsors::Types::Sponsorable, Symbol)) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { returns(T::Boolean) }
  def one_time_payment?
    frequency_param == "one-time"
  end

  sig { returns(String) }
  def frequency
    one_time_payment? ? "one_time" : "recurring"
  end

  sig { returns(Integer) }
  memoize def price_in_cents
    (params[:value].to_f * 100).to_i
  end

  sig { returns(SponsorsTier) }
  memoize def tier
    SponsorsTier.new(
      sponsors_listing: sponsorable_sponsors_listing,
      monthly_price_in_cents: price_in_cents,
      yearly_price_in_cents: price_in_cents * 12,
      frequency: frequency
    )
  end
end
