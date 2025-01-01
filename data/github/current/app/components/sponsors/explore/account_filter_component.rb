# typed: true
# frozen_string_literal: true

class Sponsors::Explore::AccountFilterComponent < ApplicationComponent
  include AvatarHelper

  TOTAL_ORGS_TO_DISPLAY = 3

  def initialize(
    filter_set: nil,
    include_current_user: true,
    container_classes: "",
    organizations: []
  )
    @filter_set = filter_set || SponsorsExploreFilterSet.new
    @include_current_user = include_current_user
    @container_classes = container_classes
    @organizations = organizations
  end

  def render?
    return false unless logged_in?

    organizations.any?
  end

  private

  attr_reader :filter_set, :organizations

  memoize def accounts_to_display
    result = []
    if logged_in? && @include_current_user && organizations.size > 0
      result << current_user
    end
    result += organizations.take(TOTAL_ORGS_TO_DISPLAY)
  end

  def remaining_orgs
    organizations.drop(TOTAL_ORGS_TO_DISPLAY)
  end

  def show_overflow_menu?
    organizations.size > TOTAL_ORGS_TO_DISPLAY
  end

  memoize def selected_account_login
    filter_set.account_login || current_user.login
  end

  def selected_account?(account)
    account.login == selected_account_login
  end

  def account_link_attributes(account)
    attrs = { class: "mr-2 pl-2 pr-2 py-2 d-flex flex-items-center filter-item" }
      .merge(test_selector_data_hash("account-link-#{account}"))
      .merge(hydro_click_attrs_for(account))

    if selected_account?(account)
      attrs["aria-current"] = "page"
    end

    attrs
  end

  def hydro_click_attrs_for(account)
    attrs = helpers.hydro_click_tracking_attributes("sponsors.explore_selected_account_change",
      account_login: account.display_login)
    attrs.map { |key, value| ["data-#{key}", value] }.to_h
  end
end
