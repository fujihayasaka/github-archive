# typed: true
# frozen_string_literal: true

class Hook::Event::SponsorshipEvent < Hook::Event
  supports_targets SponsorsListing
  description "A Sponsorship is created, updated, or cancelled."
  event_attr :action, :sponsorship_id, :actor_id, :current_tier_id, required: true
  event_attr :changes, :previous_tier_id, :pending_change_tier_id, :pending_change_on

  def sponsorship
    @sponsorship ||= Sponsorship.find(sponsorship_id)
  end

  def actor
    @actor ||= User.find(actor_id)
  end

  def previous_tier
    return unless previous_tier_id
    @previous_tier ||= SponsorsTier.find(previous_tier_id)
  end

  def pending_change_tier
    return unless pending_change_tier_id
    @pending_change_tier ||= SponsorsTier.find(pending_change_tier_id)
  end

  def current_tier
    @current_tier ||= SponsorsTier.find(current_tier_id)
  end

  def target_sponsors_listing
    sponsorship.sponsors_listing
  end
end
