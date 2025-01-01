# frozen_string_literal: true

module BlocklistedTerms
  class IndexComponent < ApplicationComponent
    include HasPagination
    include HasSearching

    attr_reader :level, :query, :term_type

    def initialize(page:, level:, term_type:, query:)
      @page = normalize_page(page)
      @level = level || "all"
      @term_type = term_type || "all"
      @query = query
    end

    def blocklisted_terms
      return @blocklisted_terms if defined? @blocklisted_terms

      blocklisted_terms = BlocklistedTerm.all
      blocklisted_terms = blocklisted_terms.where(level: @level) if @level != "all"
      blocklisted_terms = blocklisted_terms.where(term_type: @term_type) if @term_type != "all"
      blocklisted_terms = blocklisted_terms.where("pattern LIKE ?", "%#{@query}%") if @query.present?

      @blocklisted_terms = blocklisted_terms.page(@page)
    end
  end
end
