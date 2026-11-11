# typed: true
# frozen_string_literal: true

module Memex
  module EditFormFieldIteration
    class ItemComponent < ApplicationComponent
      FORMATTED_DATE_STRFTIME = "%b %d, %Y"

      def initialize(iteration:)
        @iteration = iteration
      end

      # Public: the start date and end date in the format:
      #
      # Sep 21, 2021 - Sep 28,  2021.
      #
      # The `_s` is a nod to Ruby's `to_formatted_s` method.
      #
      # Returns a String
      def date_range_formatted_s
        "#{@iteration.parsed_start.strftime(FORMATTED_DATE_STRFTIME)} - #{@iteration.end_date.strftime(FORMATTED_DATE_STRFTIME)}"
      end
    end
  end
end
