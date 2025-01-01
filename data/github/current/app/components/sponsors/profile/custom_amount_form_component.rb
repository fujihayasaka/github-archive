# typed: true
# frozen_string_literal: true

class Sponsors::Profile::CustomAmountFormComponent < ApplicationComponent
  def initialize(sponsors_listing:,
    frequency:,
    sponsor:,
    current_sponsorship_tier: nil,
    sponsors_tiers: nil,
    custom_amount: nil,
    sponsorable_metadata: {},
    previewing: false,
    selectable: true
  )
    @sponsors_listing = sponsors_listing
    @frequency = frequency
    @sponsor = sponsor
    @current_sponsorship_tier = current_sponsorship_tier
    @sponsors_tiers = sponsors_tiers
    @custom_amount = custom_amount
    @sponsorable_metadata = sponsorable_metadata
    @previewing = previewing
    @selectable = selectable
  end

  def render?
    sponsors_listing && frequency && frequency != :patreon
  end

  private

  attr_reader :sponsors_listing, :frequency, :current_sponsorship_tier

  delegate :sponsorable, to: :sponsors_listing

  def sponsors_tiers
    return @sponsors_tiers if @sponsors_tiers
    @sponsors_tiers = sponsors_listing.published_sponsors_tiers.where(frequency: frequency).to_a
    @sponsors_tiers << current_sponsorship_tier if current_sponsorship_tier
    @sponsors_tiers
  end

  def sponsor_login
    @sponsor&.login
  end

  def previewing?
    @previewing
  end

  def show_select_button?
    @selectable
  end

  def disable_submit?
    custom_amount_value.nil?
  end

  def one_time?
    frequency == :one_time
  end

  def form_action
    sponsorable_sponsorships_path(sponsorable)
  end

  def form_disabled_reason
    frequency_adjective = one_time? ? "one-time" : "monthly"
    "Select: You cannot switch from a #{current_sponsorship_tier.frequency_adjective} tier to a " \
      "#{frequency_adjective} tier"
  end

  def switching_frequency?
    return false if is_sponsored_tier?
    current_sponsorship_tier.present? && current_sponsorship_tier.frequency != frequency
  end

  # Private: Does the chosen custom amount, if any, and frequency represent the active sponsorship?
  def is_sponsored_tier?
    return false unless current_sponsorship_tier
    current_sponsorship_tier.monthly_price_in_dollars.to_i == @custom_amount &&
      frequency == current_sponsorship_tier.frequency && current_sponsorship_tier.custom?
  end

  def autofocus_custom_amount?
    @custom_amount.present?
  end

  def sponsorable_custom_tier_verify_url
    frequency_name = one_time? ? "one-time" : "recurring"
    sponsorable_custom_tier_verify_path(sponsorable, frequency: frequency_name)
  end

  memoize def custom_amount_value
    if @custom_amount
      @custom_amount_value = @custom_amount
    else
      cents = sponsors_listing.suggested_custom_tier_amount_in_cents
      @custom_amount_value = cents / 100 if cents
    end
  end

  memoize def min_custom_tier_amount
    cents = sponsors_listing.min_custom_tier_amount_in_cents
    cents / 100 if cents
  end

  def closest_lesser_tier
    return unless custom_amount_value
    tier_minimums.find { |t| custom_amount_value >= t }
  end

  def rewards_message
    return tier_reward_text if closest_lesser_tier.present?
    return default_reward_text if show_default_reward_text?

    choose_amount_text
  end

  def show_default_reward_text?
    return false unless min_custom_tier_amount
    return false unless custom_amount_value

    custom_amount_value >= min_custom_tier_amount
  end

  def tier_reward_prefix
    "You'll receive any rewards listed in the "
  end

  def tier_reward_suffix
    suffix = "#{one_time? ? "one-time" : "monthly"} tier."

    if show_public_badge_reward_text?
      # Downcase first letter
      badge_text = public_badge_reward_text.sub(public_badge_reward_text[0], public_badge_reward_text[0].downcase)
      suffix + " Additionally, " + badge_text
    else
      suffix
    end
  end

  def tier_reward_text
    tier_reward_prefix + "$#{closest_lesser_tier} " + tier_reward_suffix
  end

  def default_reward_text
    if show_public_badge_reward_text?
      public_badge_reward_text
    else
      no_reward_text
    end
  end

  def public_badge_reward_text
    "A Public Sponsor achievement will be added to your profile."
  end

  def no_reward_text
    "There are no rewards associated with this sponsorship."
  end

  def choose_amount_text
    "Choose a custom amount."
  end

  memoize def show_public_badge_reward_text?
    achievement = @sponsor&.achievements_for(Achievable::PublicSponsor)

    return true unless achievement

    achievement.empty?
  end

  # Private: Get a list of the dollar amounts of each tier in the chosen frequency,
  # ordered with the greatest amounts first.
  #
  # Returns an Array of Integers.
  memoize def tier_minimums
    sponsors_tiers.map(&:monthly_price_in_dollars).map(&:to_i).sort.reverse
  end
end
