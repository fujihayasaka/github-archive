# typed: strict
# frozen_string_literal: true

# These are just constants that hold instrumentation strings
module Marketplace
  module Events
    # Browser events
    BROWSER_ACTION_CLICK = "browser.marketplace.action.click"
    BROWSER_ACTION_DELIST = "browser.marketplace.action.delist"
    BROWSER_ACTION_USE_BUTTON_CLICK = "browser.marketplace.action_use_button.click"
    BROWSER_ACTION_USE_BUTTON_REPOSITORY_CLICK = "browser.marketplace.action_use_button_repository.click"
    BROWSER_LISTING_CLICK = "browser.marketplace_listing_click"
    BROWSER_RECOMMENDED_LISTING_CLICK = "browser.marketplace.recommended_listing.click"
    BROWSER_RECOMMENDED_PAGE_CLICK = "browser.marketplace.recommended_page.click"
    BROWSER_RECOMMENDED_PROJECT_MANAGEMENT_CLICK = "browser.marketplace.recommended_project_management.click"
    BROWSER_RECOMMENDED_PROJECT_MANAGEMENT_DISMISSED = "browser.marketplace.recommended_project_management.dismissed"
    BROWSER_RETARGETING_NOTICE_CLICK = "browser.marketplace_retargeting_notice_click"
    BROWSER_RETARGETING_NOTICE_DISMISSED = "browser.marketplace_retargeting_notice_dismissed"
    BROWSER_TRENDING_APPS_CLICK = "browser.marketplace.trending_apps.click"

    # Page views
    CREATE_EXTENSION_VIEW = "marketplace.create_extension_view"
    HOMEPAGE_VIEW = "marketplace.homepage_view"
    LISTING_VIEW = "marketplace.listing_view"

    # Others
    ACTION_LIST = "marketplace.action.list"
    ACTION_USE_BUTTON_REPOSITORY_SEARCH = "marketplace.action_use_button_repository.search"
    LISTING_INSTALL = "marketplace.listing_install"
    LISTING_STATE_CHANGE = "marketplace.listing_state_change"
    PURCHASE_PURCHASED = "marketplace.purchase_purchased"
    RECOMMENDED_LISTINGS_DISPLAYED = "marketplace.recommended_listings.displayed"
    TRENDING_APPS_DISPLAYED = "marketplace.trending_apps.displayed"
  end
end
