# frozen_string_literal: true

module CVEReviews
  class IndexComponent < ApplicationComponent
    include HasCurationState
    include HasPagination
    include HasSearching

    attr_reader :sort, :curation_state, :query

    CURATION_STATES = %w[
      in_triage
      waiting
      open
      open_update
      published
      rejected
      closed
    ].freeze

    def initialize(sort:, state:, page:, query:)
      @sort = sort || "asc"
      @curation_state = state || "open"
      @page = normalize_page(page)
      @query = query
    end

    def cve_reviews
      return @cve_reviews if defined? @cve_reviews

      @cve_reviews = CVEReview
        .preload(:cve_requests, :repository_advisory_feed_entry)
        .order(review_requested_at: @sort)
        .by_curation_state(@curation_state)
        .search_identifiers(@query)
        .page(@page)
    end

    def curation_states
      CURATION_STATES
    end
  end
end
