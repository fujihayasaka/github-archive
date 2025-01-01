# typed: true
# frozen_string_literal: true

class Sponsors::Profile::TierDisplayComponent < ApplicationComponent
  def initialize(
    tier:, sponsorable: nil,
    sponsor: nil,
    no_verified_emails: false,
    sponsorable_metadata: {},
    current_sponsorship_tier: nil,
    is_previous_sponsorship: false,
    selectable: true,
    has_active_patreon_sponsorship: false
  )
    @tier = tier
    @sponsorable = sponsorable || tier&.sponsorable
    @current_sponsorship_tier = current_sponsorship_tier
    @sponsor = sponsor
    @sponsorable_metadata = sponsorable_metadata
    @is_previous_sponsorship = is_previous_sponsorship
    @selectable = selectable
    @has_active_patreon_sponsorship = has_active_patreon_sponsorship
  end

  private

  attr_reader :tier, :sponsorable, :current_sponsorship_tier, :sponsor, :sponsorable_metadata

  def render?
    tier.present? && sponsorable.present?
  end

  def repository_errors
    tier.sponsors_only_repository_errors
  end

  def show_repo_access_message?
    repository_errors.empty? && tier.grants_repository_access_to?(sponsor)
  end

  def sponsored_tier?
    tier.id == current_sponsorship_tier&.id
  end

  def previous_sponsorship?
    @is_previous_sponsorship
  end

  def show_select_button?
    @selectable
  end

  def active_patreon_sponsorship?
    @has_active_patreon_sponsorship
  end

  def show_current_sponsorship_label?
    return false unless sponsored_tier?

    tier.recurring?
  end

  def show_previous_sponsorship_label?
    return false unless previous_sponsorship?

    tier.recurring?
  end

  def login_url
    return_to_url = sponsorable_sponsorships_path(@sponsorable, tier_id: @tier.id, sponsor: @sponsor&.login)
    login_path(return_to: return_to_url)
  end

  def submit_text
    return "Manage" if sponsored_tier? && tier.recurring?
    "Select"
  end

  def patreon_dialog_body_text
    "You already support this user on Patreon. Are you sure you want to support them on GitHub? "\
    "We will ignore your Patreon tier information and this might affect the rewards you receive."
  end
end
