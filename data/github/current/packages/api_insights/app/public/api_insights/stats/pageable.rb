# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  module Pageable
    extend T::Helpers

    abstract!
    requires_ancestor { StatsBase }

    sig { params(page: Integer, per_page: Integer).returns(T.self_type) }
    def with_paging(page:, per_page:)
      query.pager = Queries::Pager.from_page(page, per_page)
      self
    end
  end
end
