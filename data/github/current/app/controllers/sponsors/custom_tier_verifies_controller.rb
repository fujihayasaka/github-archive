# typed: strict
# frozen_string_literal: true

# not named the more sensible `CustomTierPricingChecksController` because some people
# who write adblockers think that all URLs with `pricing` should be blocked
# (which is very silly) and also a `check` means `money` in en_US so that way
# lies sadness too.
class Sponsors::CustomTierVerifiesController < ApplicationController
  extend T::Sig
  include Sponsors::SharedControllerMethods

  before_action :sponsorable_required
  before_action :non_waitlisted_sponsors_listing_required
  before_action :non_banned_sponsors_listing_required
  before_action :viewable_sponsors_listing_required
  before_action :non_spammy_user_required

  sig { void }
  def create
    respond_to do |format|
      format.html_fragment do
        if price_in_cents % 100 != 0
          error_message = "Please choose a whole-dollar amount"
        elsif !amount_valid?
          error_message = amount_errors
        elsif !price_in_cents.positive?
          error_message = "Amount must be at least $1"
        else
          return head :ok
        end

        render body: error_message, status: :unprocessable_entity,
          content_type: "text/fragment+html"
      end
    end
  end

  private

  sig { void }
  def viewable_sponsors_listing_required
    return if sponsorable_sponsors_listing&.approved?
    return if sponsorable_sponsors_listing&.adminable_by?(current_user)

    render_404
  end

  sig { returns(T.any(Symbol, GitHubSponsors::Types::Sponsorable)) }
  def target_for_conditional_access
    this_sponsorable = sponsorable
    return :no_target_for_conditional_access unless this_sponsorable.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_sponsorable
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
  def price_in_cents
    # Some users have sent invalid input here, so we want to guard against non-String, non-Integer or non-Float values.
    # See https://github.com/github/sponsors/issues/5403.
    return 0 unless params[:value].respond_to?(:to_f)
    (params[:value].to_f * 100).to_i
  end

  sig { returns(T::Boolean) }
  def amount_valid?
    return true if custom_tier.valid?
    return true if published_tier_exists?

    custom_tier.errors[:monthly_price_in_cents].none?
  end

  sig { returns(String) }
  def amount_errors
    if custom_tier.errors[:monthly_price_in_cents].size == 1 && custom_tier.monthly_price_in_cents < 1_00
      "Amount must be at least $1"
    else
      "Amount #{custom_tier.errors[:monthly_price_in_cents].last}"
    end
  end

  sig { returns(T::Boolean) }
  def published_tier_exists?
    sponsorable_sponsors_listing&.has_published_tier?(
      monthly_price_in_cents: price_in_cents,
      frequency: frequency,
    )
  end

  sig { returns(SponsorsTier) }
  memoize def custom_tier
    SponsorsTier.new(
      state: :custom,
      sponsors_listing: sponsorable_sponsors_listing,
      monthly_price_in_cents: price_in_cents,
      yearly_price_in_cents: price_in_cents * 12,
      frequency: frequency
    )
  end
end
