# typed: strict
# frozen_string_literal: true

module  SecretScanning
  class AlertQueryService
    class AlertsByRepoData
      sig do
        params(
          results: T::Array[GitHub::TokenScanning::Service::Token],
          open_count: Integer,
          resolved_count: Integer,
            open_with_links_count: Integer,
          next_cursor: T.nilable(String),
          prev_cursor: T.nilable(String)
        ).void
      end
      def initialize(results:, open_count:, resolved_count:, open_with_links_count:, next_cursor:, prev_cursor:)
        @results = results
        @open_count = open_count
        @resolved_count = resolved_count
        @open_with_links_count = open_with_links_count
        @next_cursor = next_cursor
        @prev_cursor = prev_cursor
      end
      sig { returns(T::Array[GitHub::TokenScanning::Service::Token]) }
      attr_reader :results
      sig { returns(Integer) }
      attr_reader :open_count
      sig { returns(Integer) }
      attr_reader :resolved_count
      sig { returns(Integer) }
      attr_reader :open_with_links_count
      sig { returns(T.nilable(String)) }
      attr_reader :next_cursor
      sig { returns(T.nilable(String)) }
      attr_reader :prev_cursor
    end
  end
end
