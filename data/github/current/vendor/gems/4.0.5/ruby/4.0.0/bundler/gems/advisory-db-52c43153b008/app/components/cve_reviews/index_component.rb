# frozen_string_literal: true

module CVEReviews
  class IndexComponent < ApplicationComponent
    include HasCurationState
    include HasPagination
    include HasSearching

    attr_reader :sort, :curation_state, :query, :assignee

    CURATION_STATES = %w[
      in_triage
      waiting
      open
      open_update
      published
      rejected
      closed
    ].freeze

    def initialize(sort:, state:, page:, query:, assignee: nil)
      @sort = sort || "asc"
      @curation_state = state || "open"
      @page = normalize_page(page)
      @query = query
      @assignee = assignee.presence || "all"
    end

    def cve_reviews
      return @cve_reviews if defined? @cve_reviews

      @cve_reviews = CVEReview
        .preload(:cve_requests, :repository_advisory_feed_entry)
        .order(review_requested_at: @sort)
        .by_curation_state(@curation_state)
        .by_assignee(@assignee)
        .search_identifiers(@query)
        .page(@page)
    end

    def curation_states
      CURATION_STATES
    end

    def curators
      AdvisoryDB::Config::ActiveCurators::CURATORS
    end

    def assignee_label(assignee_value)
      case assignee_value
      when "all" then "All"
      when "none" then "None"
      else assignee_value
      end
    end
  end
end
