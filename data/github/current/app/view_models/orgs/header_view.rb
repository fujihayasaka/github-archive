# typed: true
# frozen_string_literal: true

module Orgs
  class HeaderView < Orgs::OverviewView
    attr_reader :selected_nav_item

    VALID_NAV_ITEMS = %i[jobs members packages projects repos security settings
      teams verified_domains apps insights discussions security_center
      sponsoring overview]

    # Public: Get the CSS class to use for showing the selected state of the
    # specified nav item.
    #
    # nav_item - Name of nav item to get the CSS class for.
    #
    # Returns a string.
    def selected_class_for_nav_item(nav_item)
      unless valid_nav_item?(selected_nav_item)
        raise "Selected nav item (#{selected_nav_item.inspect}) is invalid. Valid ones are #{VALID_NAV_ITEMS.inspect}."
      end

      unless valid_nav_item?(nav_item)
        raise "Passed nav item (#{nav_item}) is invalid. Valid ones are #{VALID_NAV_ITEMS.inspect}."
      end

      "selected" if nav_item == selected_nav_item
    end

    private

    # Internal: Is the specified nav item valid?
    #
    # nav_item - Name of nav item to check validity of.
    #
    # Returns a boolean.
    def valid_nav_item?(nav_item)
      VALID_NAV_ITEMS.include?(nav_item)
    end
  end
end
