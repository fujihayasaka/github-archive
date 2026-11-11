# typed: true
# frozen_string_literal: true

module Elastomer
  module Slicers

    class DateSlicer < ::Elastomer::Slicer

      # Assign the slice name. This must be an String value that contains only
      # word characters in the set [a-zA-Z0-9_]. Setting the slice name to `nil`
      # will clear the attribute.
      #
      # Raises an ArgumentError if the slice name is not valid.
      def slice=(str)
        if str.nil?
          @slice = nil
        elsif str.is_a?(String) && str =~ /\A#{slice_match}\z/
          @slice = str
        else
          raise ArgumentError, "unrecognized slice name: #{str.inspect}"
        end
      end

      # Constructs a slice name based on the given value. Subclasses can override
      # this method to implement their own slicing strategies.
      #
      # value - Either an Integer number of milliseconds or a Time instance.
      #
      # Returns the slice name as a String.
      # Raises an ArgumentError if the value could not be converted to a slice.
      def slice_from_value(value)
        return value if value.is_a?(String) && value =~ /\A#{slice_match}\z/

        time =
          case value
          when Integer; Time.at(value / 1000.0)
          when Time; value
          else
            raise ArgumentError, "time value required but #{value.inspect} was given"
          end

        time.strftime("%Y-%m")
      end

      # Provides an enumerator over a range of slice names. We start with the
      # `first` and end at the `last` range. This method is very useful when
      # creating a completely new index and all slices need to be created.
      #
      # first - beginning of the range as a String or Time
      # last  - end of the range as a String or Time
      #
      # Example
      #
      #   enum = slice_range("2016-10", "2017-02")
      #   enum.to_a  #=> ["2016-10", "2016-11", "2016-12", "2017-01", "2017-02"]
      #
      #   slice_range("2016-10", "2017-02") { |slice| ... }
      #
      # Returns an Enumerator if a block is not given.
      # Raises an ArgumentError if the `first` or `last` values are unrecognized.
      def slice_range(first, last)
        first = time_from_value(first)
        last  = time_from_value(last)

        enum = Enumerator.new do |y|
          cur = first
          prev_slice = T.let(nil, T.untyped)
          while cur <= last
            slice = slice_from_value(cur)
            y << slice unless slice == prev_slice
            prev_slice = slice
            cur += 1.month
          end
        end

        if block_given?
          enum.each { |slice| yield slice }
          self
        else
          enum
        end
      end

      # Internal: Matches on slice names formatted as YYYY-MM. This is a loose
      # match so we are not validating strict year conformancy.
      def slice_match
        "\\d{4}-(?:0[1-9]|1[0-2])"
      end

      # Internal: Take a value and return a Time instance that is pinned to the
      # first day of the month for that particular value.
      #
      # value - a String or a Time
      #
      # Returns a Time instance for the first day of the month.
      def time_from_value(value)
        year = month = nil

        if value.is_a?(String) && value =~ /\A#{slice_match}\z/
          year, month = value.split("-")
          year  = year.to_i
          month = month.to_i
        elsif value.is_a?(Time)
          year  = value.year
          month = value.month
        else
          raise ArgumentError, "unrecognized time value: #{value.inspect}"
        end

        Time.utc(year, month)
      end
    end
  end
end
