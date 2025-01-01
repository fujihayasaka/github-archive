# typed: true
# frozen_string_literal: true

module Events
  class SponsorButtonComponent < ApplicationComponent
    include NewsFeedHelper

    def initialize(event:, sponsorable_user_ids:, sponsored_user_ids:, link_class: nil)
      @event = event
      @sponsorable_user_ids = sponsorable_user_ids
      @sponsored_user_ids = sponsored_user_ids
      @link_class = class_names("d-inline-block btn btn-sm", link_class)
    end

    private

    attr_reader :event, :sponsorable_user_ids, :sponsored_user_ids, :link_class

    delegate :sponsor_button_target_user_id, :sponsor_button_target_user_login,
      to: :event

    def render?
      return false unless GitHub.sponsors_enabled?
      return false unless logged_in?
      return false if atom_feed?
      event.user_is_sponsorable?(sponsorable_user_ids, viewer: current_user)
    end

    def link_data_hash
      link_test_selector_hash = if sponsoring?
        test_selector_hash("sponsoring-btn")
      else
        test_selector_hash("sponsor-btn")
      end

      event_analytics_attributes(event, "sponsor").
        merge(link_test_selector_hash).
        merge(
          hovercard_data_attributes_for_sponsors_listing(
            sponsorable_login: sponsor_button_target_user_login
          )
        )
    end

    def link_aria_label
      sponsoring? ? "Sponsoring @#{sponsor_button_target_user_login}" : "Sponsor @#{sponsor_button_target_user_login}"
    end

    def octicon_icon
      sponsoring? ? "heart-fill" : "heart"
    end

    def octicon_classes
      sponsoring? ? "icon-sponsoring" : "icon-sponsor"
    end

    def link_text
      sponsoring? ? "Sponsoring" : "Sponsor"
    end

    def sponsoring?
      sponsored_user_ids.include?(sponsor_button_target_user_id)
    end
  end
end
