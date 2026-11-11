# frozen_string_literal: true

module CVEReviews
  class TableComponent < ApplicationComponent
    include HasSorting

    attr_reader :cve_reviews, :sort

    def initialize(cve_reviews:, sort: nil)
      @cve_reviews = cve_reviews
      @sort = sort
    end

    def affected_versions_for(cve_request)
      cve_request.affected_products_payload&.first&.dig("affected_versions")
    end

    # We use this method to calculate the current CVE request for a given CVE
    # review to prevent an n+1 query problem. If we were to call
    # CVEReview#current_cve_request, we'd perform an additional database query
    # for every row in the list. This way, we can use the preloaded
    # CVEReview#cve_requests association.
    def current_cve_request(cve_review)
      cve_review.cve_requests.max_by(&:id)
    end

    def package_for(cve_request)
      cve_request.affected_products_payload&.first&.dig("package")
    end

    def patches_for(cve_request)
      cve_request.affected_products_payload&.first&.dig("patches")
    end
  end
end
