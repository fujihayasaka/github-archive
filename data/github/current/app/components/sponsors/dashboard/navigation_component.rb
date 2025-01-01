# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::NavigationComponent < ApplicationComponent
  DEFAULT_SELECTED_TAB = :overview
  SELECTED_TABS = [
    DEFAULT_SELECTED_TAB,
    :fiscal_host,
    :profile,
    :goals,
    :tiers,
    :sponsors,
    :updates,
    :webhooks,
    :payouts,
    :settings,
  ].freeze

  def initialize(sponsors_listing:, selected_tab: DEFAULT_SELECTED_TAB)
    @sponsors_listing = sponsors_listing
    @selected_tab = fetch_or_fallback(SELECTED_TABS, selected_tab)
  end

  private

  attr_reader :sponsors_listing, :selected_tab

  delegate :sponsorable_login, to: :sponsors_listing

  def render?
    sponsors_listing.present? && !sponsors_listing.disabled? && GitHub.sponsors_enabled? && logged_in?
  end

  def show_settings_alert_icon?
    sponsors_listing.encourage_setting_country_of_residence? || !contact_email_verified?
  end

  def contact_email_verified?
    sponsors_listing.for_organization? || sponsors_listing.contact_email&.verified?
  end
end
