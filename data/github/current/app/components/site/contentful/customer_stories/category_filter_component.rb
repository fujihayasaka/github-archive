# typed: true
# frozen_string_literal: true

class Site::Contentful::CustomerStories::CategoryFilterComponent < ApplicationComponent
  include UrlHelpers

  ORDERED_CATEGORIES = %w[
    All
    Enterprise
    Team
  ].freeze

  ORDERED_INDUSTRIES = [
    "All",
    "Advertising & Marketing",
    "Automotive",
    "Education",
    "Energy & Utilities",
    "Financial services",
    "Food & Beverage",
    "Government",
    "Healthcare & Life Sciences",
    "Manufacturing",
    "Media & Entertainment",
    "Nonprofit",
    "Professional services",
    "Real Estate",
    "Retail & ecommerce",
    "Social & Messaging",
    "Software, Hardware & Technology",
    "Telecommunications",
    "Transportation & Logistics",
    "Travel & Hospitality",
  ].freeze

  ORDERED_REGIONS = [
    "All",
    "Americas",
    "Asia Pacific",
    "Europe",
    "Middle East & Africa",
  ].freeze

  ORDERED_TYPES = %w[
    All
    Enterprise
    Team
  ].freeze

  ORDERED_SIZES = %w[
    Startup
    Growth
    Enterprise
  ].freeze

  ORDERED_FEATURES = [
    "All",
    *Site::Contentful::CustomerStories::CustomerStory::ORDERED_STORY_PRODUCTS.values.sort
  ].freeze

  LIST_TYPE_MAPPING = {
    industry: ORDERED_INDUSTRIES,
    region: ORDERED_REGIONS,
    type: ORDERED_TYPES,
    size: ORDERED_SIZES,
    feature: ORDERED_FEATURES,
  }.freeze

  def initialize(category:, filter:, existing_params: {})
    @category = category
    @filter_name = filter
    @existing_params = existing_params
  end

  def render?
    ORDERED_CATEGORIES.include?(@category.titleize) && LIST_TYPE_MAPPING.keys.include?(@filter_name)
  end

  def active_filter_option
    filter_value = @existing_params[@filter_name]
    filter_name_for(@filter_name, filter_value) if filter_value.present?
  end

  def filter_display_title
    active_filter_option ? "#{@filter_name.to_s.titleize}: #{active_filter_option}" : @filter_name.to_s.titleize
  end

  def filter_options_for(filter)
    LIST_TYPE_MAPPING.fetch(filter, [])
  end

  def filter_name_for(filter, filter_param)
    filter_options_for(filter).find do |entry|
      CGI.escape(entry) == filter_param
    end
  end

  private

  def build_filter_option_link(category, filter_name, filter_option, existing_params = {})
    filter_value = CGI.escape(filter_option)
    category_customer_stories_path(category, params: existing_params.merge(filter_name => filter_value), anchor: "browse")
  end
end
