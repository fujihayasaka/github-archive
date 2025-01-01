# typed: true
# frozen_string_literal: true

module Search
  module Filters
    # KeywordDateRangeFilter builds lexical date range queries for keyword-like
    # fields storing ISO8601 date strings (YYYY-MM-DD). It converts partial
    # inputs (year, month) into explicit start/end day bounds so lexicographic
    # comparisons match the stored values. For flattened fields, it also ensures
    # both bounds are present by supplying sentinel values when needed.
    class KeywordDateRangeFilter < DateRangeFilter
      # Use sentinels within DateRangeFilter's allowed year range (1970..2970)
      MIN_SENTINEL = "1970-01-01"
      MAX_SENTINEL = "2970-12-31"

      # Build a lower-bound (inclusive) start and the next period's start (exclusive)
      # for a given ISO8601-like partial date value.
      # Returns [start_str, next_start_str, granularity] where granularity is
      # one of :year, :month, :day, or :other when not matched.
      def period_bounds(value)
        return [nil, nil, :other] if value.nil?

        v = value.to_s.strip

        # Use the DateRangeFilter parser to recognize valid date parts.
        # Allow InvalidRange exceptions to propagate so validation works properly.
        parts = parse_date_time(v)

        case parts.length
        when 1 # year
          year = parts[0]
          start = format("%04d-01-01", year)
          nxt   = format("%04d-01-01", year + 1)
          [start, nxt, :year]
        when 2 # year-month
          year, month = parts
          if month < 12
            next_year = year
            next_month = month + 1
          else
            next_year = year + 1
            next_month = 1
          end
          start = format("%04d-%02d-01", year, month)
          nxt   = format("%04d-%02d-01", next_year, next_month)
          [start, nxt, :month]
        when 3 # year-month-day
          year, month, day = parts
          day_str = format("%04d-%02d-%02d", year, month, day)
          [day_str, day_str, :day]
        when 4, 5, 6, 7 # time values (includes hour, minute, second, zone)
          # For full datetime strings, treat as exact value
          [v, v, :time]
        end
      end

      # Ensure both bounds exist for flattened keyword behavior without changing
      # already-present operators.
      def ensure_both_bounds!(hash)
        return hash if hash.nil? || hash.empty?

        if (hash.key?(:gt) || hash.key?(:gte)) && !(hash.key?(:lt) || hash.key?(:lte))
          hash[:lte] = MAX_SENTINEL
        elsif (hash.key?(:lt) || hash.key?(:lte)) && !(hash.key?(:gt) || hash.key?(:gte))
          hash[:gte] = MIN_SENTINEL
        end
        hash
      end

      # Build lexical range bounds without ES date-math rounding.
      def range_filter_hash(comparator, value, from, to)
        bounds = {}

        if comparator
          # Single-sided comparator
          start, nxt, gran = period_bounds(value)
          case gran
          when :year, :month
            # Validate the normalized start (catches invalid months like 13)
            validate_value(start)
            case comparator
            when ">"
              bounds[:gte] = nxt
            when ">="
              bounds[:gte] = start
            when "<"
              bounds[:lt] = start
            when "<="
              bounds[:lt] = nxt
            end
          else
            # Day or other granularities: use comparator as-is
            case comparator
            when ">"
              bounds[:gt] = value
            when ">="
              bounds[:gte] = value
            when "<"
              bounds[:lt] = value
            when "<="
              bounds[:lte] = value
            end
          end
        else
          # Range form from..to
          if from && from != "*"
            f_start, _f_next, f_gran = period_bounds(from)
            if f_gran == :year || f_gran == :month
              validate_value(f_start)
              bounds[:gte] = f_start
            else
              bounds[:gte] = from
            end
          end

          if to && to != "*"
            t_start, t_next, t_gran = period_bounds(to)
            if t_gran == :year || t_gran == :month
              validate_value(t_start)
              bounds[:lt] = t_next
            else
              bounds[:lte] = to
            end
          end
        end

        ensure_both_bounds!(bounds)
        validate_range_hash(bounds)
        { range: { field => bounds } } if bounds.present?
      end

      # Single value => exact day match (stored ISO date strings).
      def range_filter_value(value)
        return if value.nil?
        start, nxt, gran = period_bounds(value)
        case gran
        when :year, :month
          validate_value(start)
          bounds = { gte: start, lt: nxt }
          validate_range_hash(bounds)
          { range: { field => bounds } }
        when :day, :time
          validate_value(value)
          { range: { field => { gte: value, lte: value } } }
        end
      end

      # Override: Handle special :exists and :missing symbols like TermFilter does
      def build(values)
        return if values.blank? || !valid?

        if values.include?(:missing)
          { bool: { must_not: { exists: { field: field } } } }
        elsif values.include?(:exists)
          { exists: { field: field } }
        else
          super
        end
      end

      # Override to preserve :exists/:missing symbols during initialization
      def range_filter_for(value)
        return value if value == :exists || value == :missing
        super
      end
    end
  end
end
