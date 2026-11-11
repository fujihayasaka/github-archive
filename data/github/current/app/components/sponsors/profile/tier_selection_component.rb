# typed: true
# frozen_string_literal: true

class Sponsors::Profile::TierSelectionComponent < ApplicationComponent
  include AvatarHelper

  # sponsorable - a sponsorable User or Organization
  # sponsor - a User or Organization that is sponsoring this sponsorable, or nil if the current user isn't sponsoring.
  # sponsorship - an active Sponsorship, or nil.
  # previewing - a Boolean representing whether the sponsorable is previewing their SponsorsListing.
  # custom_amount - an Integer representing how much the custom amount should be, or nil.
  # frequency - Symbol or String representing the tier frequency. For example: :recurring, :one_time, :patreon.
  # editing - Boolean representing whether the sponsor is editing their Sponsorship for this Sponsorable.
  # sponsorable_metadata - a Hash of metadata, or nil.
  def initialize(sponsorable:,
                 sponsor:,
                 sponsorship:,
                 previewing:,
                 custom_amount:,
                 frequency:,
                 editing:,
                 sponsorable_metadata:)
    @sponsorable = sponsorable
    @sponsor = sponsor
    @sponsorship = sponsorship
    @previewing = previewing
    @custom_amount = custom_amount
    @frequency = frequency.to_sym
    @editing = editing
    @sponsorable_metadata = sponsorable_metadata || {}
  end

  private

  attr_reader :sponsorable, :sponsorship

  def sponsoring?
    sponsorship.present? && sponsorship.active?
  end

  def github_sponsoring?
    sponsoring? && sponsorship.github?
  end

  def show_frequency_selector?
    !current_recurring_sponsor?
  end

  def changing_tiers?
    @editing
  end

  def recurring?
    @frequency == :recurring
  end

  def one_time?
    @frequency == :one_time
  end

  def patreon?
    @frequency == :patreon
  end

  memoize def all_published_tiers
    sponsors_listing.published_sponsors_tiers.includes(:repository)
  end

  memoize def sponsors_tiers
    tiers = all_published_tiers.select { |tier| tier.frequency.to_sym == @frequency }

    if custom_tier_of_same_frequency?
      tiers << sponsorship.tier if sponsorship.tier.recurring?
    end

    tiers.sort_by(&:monthly_price_in_cents)
  end

  def custom_tier_of_same_frequency?
    return false unless sponsorship

    sponsorship.custom_tier? && sponsorship.tier.frequency.to_sym == @frequency
  end

  def previewing?
    @previewing
  end

  def path_params
    @sponsorable_metadata.merge(preview: previewing?, editing: @editing)
  end

  memoize def sponsors_listing
    sponsorable.sponsors_listing
  end

  memoize def no_verified_emails?
    return true unless logged_in?
    @sponsor.no_verified_emails?
  end

  def current_tier
    return unless sponsorship

    if pending_downgrade?
      pending_tier_change.subscribable
    else
      sponsorship.tier
    end
  end

  def previous_tier
    return nil unless pending_downgrade?
    sponsorship.tier
  end

  def pending_downgrade?
    return false unless pending_tier_change?
    !pending_tier_change.cancellation?
  end

  memoize def pending_cancellation?
    pending_tier_change&.cancellation?
  end

  # Fetch any pending plan change items for the
  # current user. This is necessary for rendering the
  # plan_pricing sub-component which displays a pending
  # downgrade or cancellation notice
  memoize def pending_tier_change
    return unless logged_in?
    return unless sponsorship
    sponsorship.pending_subscription_item_change
  end

  def pending_tier_change?
    pending_tier_change.present?
  end

  def sponsors_profile_url
    sponsorable_url(@sponsorable, sponsor: @sponsor)
  end

  def can_create_sponsorship?
    return false unless logged_in?
    return false if invoiced_org_without_sponsors_invoicing?
    return false if no_verified_emails?

    sponsorship_adminable_by_current_user?
  end

  def sponsor_is_current_user?
    @sponsor == current_user
  end

  memoize def sponsorship_adminable_by_current_user?
    logged_in? &&
      current_user.potential_sponsor_ids.include?(@sponsor.id)
  end

  memoize def sponsorable_via_patreon?
    sponsorable.sponsorable_via_patreon?
  end

  def current_recurring_sponsor?
    sponsoring? && sponsorship.recurring_payment? && !sponsorship.patreon?
  end

  def tier_selection_header_text
    if current_recurring_sponsor? && !changing_tiers?
      "Add a one-time payment"
    elsif sponsorable_via_patreon?
      "Select"
    else
      "Select a tier"
    end
  end

  def frequency_tab_path(frequency)
    if @editing
      edit_sponsorable_sponsorships_path(sponsorable, frequency: frequency, sponsor: @sponsor, **@sponsorable_metadata)
    else
      sponsorable_path(sponsorable, frequency: frequency, sponsor: @sponsor, **@sponsorable_metadata)
    end
  end

  def current_sponsored_tier?(tier)
    return false unless tier
    tier.id == current_tier&.id
  end

  memoize def one_time_payment_still_processing?
    return false unless one_time?
    @sponsor.processing_one_time_payment_to?(@sponsorable)
  end

  memoize def invoiced_org_without_sponsors_invoicing?
    return false unless logged_in?
    @sponsor.invoiced? && !@sponsor.sponsors_invoiced?
  end
end
