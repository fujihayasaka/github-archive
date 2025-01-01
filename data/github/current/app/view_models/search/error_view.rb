# typed: true
# frozen_string_literal: true

module Search
  # Helpers for rendering detailed error messages raised by executing the query.
  class ErrorView
    QUERY_ERROR_TYPES = %w(query_parsing query_generation).freeze

    # Create a new error view model
    #
    # details - An array of detailed error messages
    def initialize(details)
      @details = details
    end

    def only_query_errors?
      @details.present? && query_errors.size == @details.size
    end

    def query_errors
      @query_errors ||= @details.select { |error| QUERY_ERROR_TYPES.include?(error["type"]) }
    end

    def query_error_messages
      query_errors.map { |error| error["message"].capitalize }
    end

    def query_error_ranges
      @query_error_ranges ||= query_errors.select do |error|
        error["meta"] && error["meta"]["begin"] && error["meta"]["end"]
      end
    end

    def error_at_index?(index)
      query_error_ranges.any? do |error|
        index >= error["meta"]["begin"] && index < error["meta"]["end"]
      end
    end

    # Check the query for errors and yield each part of the string and whether
    # it is covered by any of the query errors. Yields the string segment
    # and a boolean of whether an error covers that segment.
    #
    # This is used for marking up the string with styling for the locations
    # of query errors.
    #
    # query - The query string to process.
    def query_segments_with_errors(query)
      offset = 0
      in_error = T.let(false, T::Boolean)
      query_index_range = T.let((0...query.length), T::Range[Integer])

      query_index_range.each do |index|
        error_at_index = error_at_index?(index)
        if error_at_index != in_error
          yield query[offset...index], in_error
          in_error = error_at_index
          offset = index
        end
      end

      # Yield the remaining part of the string that hasn't been covered yet
      if offset < query.length
        yield query[offset...query.length], in_error
      end
    end
  end
end
