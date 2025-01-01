# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # A range filter for date expressions. Since date expressions take more
    # forms than numeric ranges, they are handled by a separate Filter class.
    # Otherwise this is interchangeable with RangeFilter and has the same
    # semantics.
    class DateRangeFilter < RangeFilter

      # Internal: Given the arguments parsed out of a range expression, build a
      # range filter document the way ElasticSearch wants it. If comparator is
      # nil, then value is ignored and the range filter is constructed using
      # from and to.
      #
      # comparator - Optional comparator string. One of ">", ">=", "<", or "<=".
      # value      - Optional single value referenced by comparator.
      # from       - Beginning of range. Only used when comparator is nil.
      # to         - End of range. Only used when comparator is nil.
      #
      # Returns a range filter document Hash or nil if the range is not a
      # meaningful constraint (eg *..*)
      def range_filter_hash(comparator, value, from, to)
        hash = {}

        value = value.dup unless value.nil?
        from  = from.dup  unless from.nil?
        to    = to.dup    unless to.nil?

        case comparator
        when ">";  hash[:gt]  = value
        when ">="; hash[:gte] = value
        when "<";  hash[:lt]  = value
        when "<="; hash[:lte] = value
        else
          hash[:gte] = from if from != "*"
          hash[:lte] = to   if to != "*"
        end

        begin
          validate_range_hash(hash)
        rescue InvalidRangeOrder # If the range is backwards, swap it around
          hash[hash.key?(:gte) ? :gte : :gt] = to
          hash[hash.key?(:lte) ? :lte : :lt] = from
        end

        apply_rounding(hash)

        { range: { field => hash } } if hash.present?
      end

      def apply_rounding(hash)
        hash.each_value do |value|
          case value.length
          when 4;  value.concat("||/y")  # year   2016
          when 7;  value.concat("||/M")  # month  2016-09
          when 10; value.concat("||/d")  # day    2016-09-24
          when 13; value.concat("||/h")  # hour   2016-09-24T14
          end
        end
      end

      # Internal: If the range expression is a single value, then fall back to
      # this method to try and generate a term filter.
      #
      # A date value looks like the following:
      #
      # * '2013-12-12' or '2013-12-12T17:10:15Z' or any ISO8601 date/time value
      # * TODO "today" or "yesterday"
      # * TODO "2 weeks ago" (fuzzy ranges)
      # * TODO "-2d" or "-1w" This should be equivalent to -2d..*
      # * TODO "-2y..-2w"
      # * TODO "now-2w" (Elasticsearch internal format)
      # * TODO "2011-12-27||+1M/d (Elasticsearch internal 2011-12-27 plus 1 month rounded to a day)
      #
      # value - The single value
      #
      # Returns nil or a filter Hash.
      def range_filter_value(value)
        return if value.nil?

        ary = parse_date_time(value)
        if ary.length < 5  # year, month, day, hour will encompass the whole period
          range_filter_hash(nil, nil, value, value)
        else
          validate_value(value)
          build_term_filter(field, value)
        end
      end

      # Raises an InvalidRange exception if the value is invalid.
      def validate_value(value)
        ary = parse_date_time(value)
        DateTime.new(*ary)

        year = ary.first
        if year < 1970 || year > 2970
          raise InvalidRange, "The year #{year.inspect} in #{value.inspect} is outside the accepted range 1970 to 2970."
        end
      rescue ArgumentError
        invalid! value
      end

      # Returns an Array of [year, month, day, hour, minute, second, zone]
      # Raises InvalidRange if `value` is not a valid date-time
      def parse_date_time(value)
        hash = { year: nil, mon: nil, mday: nil, hour: nil, min: nil, sec: nil, zone: nil }
        date_time = T.let(nil, T.untyped)

        # If the value has *no* numbers, we can presume it's not a valid date.
        # This helps protect against users trying to search by things like
        # booleans and causing this to error
        if /\d/.match(value)
          date_time =
            case value.length
            when 4;  DateTime._strptime(value, "%Y")
            when 7;  DateTime._strptime(value, "%Y-%m")
            when 10; DateTime._strptime(value, "%Y-%m-%d")
            when 13; DateTime._strptime(value, "%Y-%m-%dT%H")
            when 16; DateTime._strptime(value, "%Y-%m-%dT%H:%M")
            when 19; DateTime._strptime(value, "%Y-%m-%dT%H:%M:%S")
            else
              date = begin
                DateTime.parse(value)
              rescue Date::Error
                invalid!(value)
              end

              date_parts = hash.keys

              # Build the needed hash from the parsed DateTime object
              date_parts.each_with_object({}) do |date_part, h|
                h[date_part] = date.public_send(date_part)
              end
            end
        else
          invalid!(value)
        end


        if date_time.nil? || date_time.key?(:leftover)
          invalid!(value)
        end

        hash.merge!(date_time)
        hash.values.compact
      end

      def invalid!(value)
        raise InvalidRange,
          "#{value.inspect} is not a recognized date/time format. " +
          "Please provide an ISO 8601 date/time value, such as YYYY-MM-DD."
      end

      # Override: Don't want to build a numeric value from a possible timestamp
      def try_numeric(value)
        value
      end
    end
  end
end
