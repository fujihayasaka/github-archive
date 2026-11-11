# typed: true
# frozen_string_literal: true

class Sponsors::Explore::SortMenuComponent < ApplicationComponent
  # These values are those in hydro.schemas.github.sponsors.v1.ExploreSortingChange.SortOption. Any new values
  # need to be added in github/hydro-schemas to the SortOption enum there first. Ideally, values here are the same
  # as the sort options presented in SponsorsExploreLoader.
  HYDRO_UNKNOWN_SORT_OPTION = "UNKNOWN"
  HYDRO_SORT_OPTIONS = %w(MOST_USED LEAST_USED MOST_SPONSORS FEWEST_SPONSORS NEWEST_SPONSORS_PROFILE
    OLDEST_SPONSORS_PROFILE).freeze

  # total_results_in_page - Integer indicating how many maintainers or dependencies are shown on the current page
  # filter_set - a SponsorsExploreFilterSet
  # enable_links - Boolean indicating whether sort options should be rendered as clickable links or if the menu
  #                should be disabled
  def initialize(total_results_in_page:, filter_set: nil, enable_links: true)
    @filter_set = filter_set || SponsorsExploreFilterSet.new
    @enable_links = !!enable_links
    @total_results_in_page = total_results_in_page
  end

  private

  attr_reader :filter_set, :total_results_in_page

  delegate :sort_by, to: :filter_set

  def render?
    GitHub.sponsors_enabled? && sort_by.present? && total_results_in_page.positive? && logged_in?
  end

  def sort_path_for(value)
    sponsors_explore_index_path(filter_set.with(sort_by: value).query_args)
  end

  def enable_links?
    @enable_links
  end

  memoize def sort_options
    SponsorsHelper::MAINTAINER_SORT_OPTIONS
  end

  def hydro_click_attrs_for(sort_value)
    sort_option = if HYDRO_SORT_OPTIONS.include?(sort_value)
      sort_value
    else
      HYDRO_UNKNOWN_SORT_OPTION
    end
    helpers.hydro_click_tracking_attributes("sponsors.explore_sorting_change", sort_option: sort_option)
  end
end
