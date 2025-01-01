# frozen_string_literal: true

module Labels
  class IndexComponent < ApplicationComponent
    include HasPagination
    include HasSearching

    attr_reader :query

    def initialize(page:, query:)
      @page = normalize_page(page)
      @query = query
    end

    def labels
      return @labels if defined? @labels

      @labels = Label.preload(:advisory_reviews).with_name_like(query).page(@page)
    end
  end
end
