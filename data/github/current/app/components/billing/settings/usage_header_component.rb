# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class UsageHeaderComponent < ApplicationComponent
      MAX_GRID_COLUMNS = 12

      attr_reader :primary_header_span

      def initialize(headers:, primary_header_span: 6)
        @headers = headers
        @primary_header_span = primary_header_span
        raise ArgumentError, "Two or more headers are required" if @headers.length < 2
        raise ArgumentError, "#{@primary_header_span} + (#{headers.size} x #{header_span}) exceeds maximum of #{MAX_GRID_COLUMNS} grid columns" if header_span < 1
      end

      def primary_header
        @headers.first
      end

      memoize def header_span
        (MAX_GRID_COLUMNS - @primary_header_span) / (@headers.length - 1)
      end

      def other_headers
        @headers[1..-1]
      end
    end
  end
end
