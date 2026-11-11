# typed: true
# frozen_string_literal: true

module DependencyReview
  class PageMetadata
    attr_reader :page, :per_page, :first, :last

    def initialize(page:, per_page:, first:, last:)
      @page = page
      @per_page = per_page
      @first = first
      @last = last
    end

    def self.from_twirp(twirp_page_metadata)
      self.new(
        page: twirp_page_metadata.page,
        per_page: twirp_page_metadata.per_page,
        first: twirp_page_metadata.first,
        last: twirp_page_metadata.last
      )
    end
  end
end
