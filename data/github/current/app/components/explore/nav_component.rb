# typed: true
# frozen_string_literal: true

module Explore
  class NavComponent < ApplicationComponent
    include ::ExploreHelper

    SHOW_SPACER_DEFAULT = false
    SHOW_SPACER_OPTIONS = [true, SHOW_SPACER_DEFAULT]

    def initialize(show_spacer: SHOW_SPACER_DEFAULT)
      @show_spacer = fetch_or_fallback(SHOW_SPACER_OPTIONS, show_spacer, SHOW_SPACER_DEFAULT)
    end

    private

    def has_newsletter_subscription?
      logged_in? && current_user.newsletter_subscriptions.active.exists?(name: "explore")
    end

    def explore_click_context
      :NAVIGATION_BAR
    end
  end
end
