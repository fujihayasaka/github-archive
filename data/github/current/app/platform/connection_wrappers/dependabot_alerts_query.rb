# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class DependabotAlertsQuery < ConnectionWrappers::Base
      include CursorGenerator
      include GitHub::Memoizer

      def initialize(*args, **kwargs)
        super
        protect_against_duplicate_cursor_parameters!
      end

      sig { returns(T::Boolean) }
      def has_next_page
        results.has_next_page
      end

      sig { returns(T::Boolean) }
      def has_previous_page
        results.has_previous_page
      end

      sig { returns(T.nilable(String)) }
      def start_cursor
        results.start_cursor
      end

      sig { returns(T.nilable(String)) }
      def end_cursor
        results.end_cursor
      end

      sig { params(item: RepositoryVulnerabilityAlert).returns(T.nilable(String)) }
      def cursor_for(item)
        search_result = results.results.find { |result| result.dig("_source", "id") == item.id }
        Search::Responses::PropertyEncoder.encode(search_result&.dig("sort"))
      end

      sig { returns(Integer) }
      memoize def total_count
        results.total
      end

      sig { returns(Search::Responses::CursorPaginationResponse) }
      memoize def results
        @items.execute
      end

      sig { returns(Promise[T::Array[RepositoryVulnerabilityAlert]]) }
      memoize def edge_nodes
        ::Promise.resolve(self.results.models)
      end

      private

      def protect_against_duplicate_cursor_parameters!
        # We need to build out support for before and after. Until then, let's
        # raise an exception.
        if before.present? && after.present?
          raise Errors::DuplicateBeforeAfterPaginationBoundaries.new
        end
      end
    end
  end
end
