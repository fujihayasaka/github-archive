# typed: strict
# frozen_string_literal: true

module IssuesDashboardSurface
  module Payloads
    class SearchResults
      sig do
        params(
          results: T::Array[Issue],
          pagination: DashboardSurface::Pagination,
          error: T.nilable(String),
        ).void
      end
      def initialize(results, pagination, error = nil)
        @results = results
        @pagination = pagination
        @error = error
      end

      sig do
        params(
          results: T::Array[Issue],
          pagination: DashboardSurface::Pagination,
          error: T.nilable(String),
        ).returns({
          results: T::Array[IssueResult],
          pageInfo: {
            currentPage: Integer,
            totalPages: Integer,
            totalCount: Integer
          },
          error: T.nilable(String)
        })
      end
      def self.serialize(results:, pagination:, error: nil)
        new(results, pagination, error).serialize
      end

      sig do returns({
        results: T::Array[IssueResult],
        pageInfo: {
          currentPage: Integer,
          totalPages: Integer,
          totalCount: Integer },
        error: T.nilable(String)
      })
      end
      def serialize
        {
          results: @results.map do |issue|
            IssueResult.serialize(issue)
          end,
          pageInfo: {
            currentPage: @pagination.current_page,
            totalPages: @pagination.total_pages,
            totalCount: @pagination.total_count,
          },
          error: @error,
        }
      end
    end
  end
end
