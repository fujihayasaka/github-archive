# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::ResponsiveMenuComponent < ApplicationComponent
  # sponsors_listing - a SponsorsListing
  # selected_tab - a Symbol representing the selected tab. Must be a Symbol matching the tabs in the
  #   Sponsors::Dashboard::NavigationComponent::SELECTED_TABS constant.
  def initialize(sponsors_listing:, selected_tab: Sponsors::Dashboard::NavigationComponent::DEFAULT_SELECTED_TAB)
    @sponsors_listing = sponsors_listing
    @selected_tab = fetch_or_fallback(Sponsors::Dashboard::NavigationComponent::SELECTED_TABS, selected_tab)
  end

  private

  attr_reader :sponsors_listing, :selected_tab

  def render?
    sponsors_listing.present? && !sponsors_listing.disabled? && GitHub.sponsors_enabled? && logged_in?
  end
end
