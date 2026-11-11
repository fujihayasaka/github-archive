# typed: true
# frozen_string_literal: true

module Site::CustomerStoriesFeedHelper
  ORDERED_INDUSTRIES = [
    "All",
    "Software & Technology",
    "Retail & eCommerce",
    "Travel & Hospitality",
    "Media & Entertainment",
    "Manufacturing",
    "Operations & Logistics",
    "Automotive",
    "Financial Services",
    "Healthcare",
    "Marketing & Communications",
    "Communications",
    "Energy & Utilities",
    "Non-Profit",
    "Government",
    "Education",
  ]

  ORDERED_REGIONS = %w[
    All
    Americas
    APAC
    EMEA
  ]

  ORDERED_TYPES = %w(
    All
    Developers
    Enterprise
    Team
  )

  LIST_TYPE_MAPPING = {
    industry: ORDERED_INDUSTRIES,
    region: ORDERED_REGIONS,
    type: ORDERED_TYPES,
  }

  def filter_name_for(filter, filter_param)
    filter_list_for(filter).find do |entry|
      entry.parameterize == filter_param
    end
  end

  def filter_list_for(filter, existing_filters = {})
    filter_list = LIST_TYPE_MAPPING.fetch(filter, []).select do |filter_entry|
      filter != :industry || story_exists_for_industry?(filter_entry, existing_filters)
    end

    filter_list.compact
  end

  def story_exists_for_industry?(filter_entry, existing_filters)
    return true if filter_entry == "All"

    ExploreFeed::CustomerStory
      .all
      .filter_by_region(existing_filters[:region])
      .filter_by_type(existing_filters[:type])
      .any? do |story|
      story.industry_filters && story.industry_filters.include?(filter_entry.parameterize)
    end
  end
end
