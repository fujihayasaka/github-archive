# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Payloads
    class SearchResults
      sig do
        params(
          results: T::Array[PullRequest],
          pagination: DashboardSurfaceController::Pagination,
          categories_by_pr_id: T::Hash[Integer, String],
        ).void
      end
      def initialize(results, pagination, categories_by_pr_id)
        @results = results
        @pagination = pagination
        @categories_by_pr_id = categories_by_pr_id
      end

      sig do
        params(
          results: T::Array[PullRequest],
          pagination: DashboardSurfaceController::Pagination,
          categories_by_pr_id: T.nilable(T::Hash[Integer, String]),
        ).returns({ results: T::Array[PullRequestResult], pageInfo: { currentPage: Integer, totalPages: Integer, totalCount: Integer } })
      end
      def self.serialize(results, pagination, categories_by_pr_id = nil)
        categories_by_pr_id = T.let(categories_by_pr_id || {}, T::Hash[Integer, String])
        new(results, pagination, categories_by_pr_id).serialize
      end

      sig { returns({ results: T::Array[PullRequestResult], pageInfo: { currentPage: Integer, totalPages: Integer, totalCount: Integer } }) }
      def serialize
        {
          results: @results.map do |result|
            serializer = case result
            when PullRequest
              PullRequestResult
            else
              T.absurd(result)
            end
            serializer.serialize(result, category: @categories_by_pr_id[result.id])
          end,
          pageInfo: {
            currentPage: @pagination.current_page,
            totalPages: @pagination.total_pages,
            totalCount: @pagination.total_count,
          }
        }
      end
    end
  end
end
