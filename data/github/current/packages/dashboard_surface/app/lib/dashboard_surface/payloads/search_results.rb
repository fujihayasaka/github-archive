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
          error: T.nilable(String),
          viewer: T.nilable(User),
        ).void
      end
      def initialize(results, pagination, categories_by_pr_id, error = nil, viewer: nil)
        @results = results
        @pagination = pagination
        @categories_by_pr_id = categories_by_pr_id
        @error = error
        @viewer = viewer
      end

      sig do
        params(
          results: T::Array[PullRequest],
          pagination: DashboardSurfaceController::Pagination,
          categories_by_pr_id: T.nilable(T::Hash[Integer, String]),
          error: T.nilable(String),
          viewer: T.nilable(User),
        ).returns({
          results: T::Array[PullRequestResult],
          pageInfo: {
            currentPage: Integer,
            totalPages: Integer,
            totalCount: Integer
          },
          error: T.nilable(String)
        })
      end
      def self.serialize(results:, pagination:, categories_by_pr_id: nil, error: nil, viewer: nil)
        categories_by_pr_id = T.let(categories_by_pr_id || {}, T::Hash[Integer, String])
        new(results, pagination, categories_by_pr_id, error, viewer: viewer).serialize
      end

      sig do returns({
        results: T::Array[PullRequestResult],
        pageInfo: {
          currentPage: Integer,
          totalPages: Integer,
          totalCount: Integer },
        error: T.nilable(String)
      })
      end
      def serialize
        {
          results: @results.map do |result|
            serializer = case result
            when PullRequest
              PullRequestResult
            else
              T.absurd(result)
            end
            serializer.serialize(result, category: @categories_by_pr_id[result.id], viewer: @viewer)
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
