# typed: true
# frozen_string_literal: true

module Site::CustomerStories
  module StoryFilteringAndPagination
    include Kernel
    extend ActiveSupport::Concern

    FILTER_TO_FIELD_MAPPING = {
      industry: :industry_filters,
      region: :regions,
      feature: :product_filters,
      category: :categories,
      size: :size,
    }.freeze

    def filter_params
      params
        .slice(*allowed_filters)
        .permit(*allowed_filters)
    end

    def normalized_filter_params
      return {} if filter_params.empty?

      filter_params.to_h.map do |filter, value|
        next if value.casecmp?("all")
        [FILTER_TO_FIELD_MAPPING.fetch(filter.to_sym, filter), CGI.unescape(value)]
      end.compact.to_h
    end

    def next_offset
      (params[:offset] || 0).to_i + stories_per_page
    end

    def show_load_more_button?(stories)
      stories.size >= stories_per_page
    end

    def allowed_filters
      raise NotImplementedError, "You must define `allowed_filters` in #{self.class.name}"
    end

    # Defined here to satisfy Sorbet
    def params
      super
    end

    private

    def stories_per_page
      Site::Contentful::CustomerStories::Pages::CategoryPage::NUMBER_OF_STORIES_PER_PAGE
    end
  end
end
