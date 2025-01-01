# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # A range filter is used to restrict search results to the set of
    # documents where a field value falls within a given range. The range can
    # be specified as a 'low' and 'high' with two dots separating them -
    # '42..69'. Either value can be a '*' indicating that it is unlimited. The
    # low and high values should NOT contain any whitespace characters.
    #
    # If a plain value is given that does not conform to the 'low..high'
    # syntax then a term filter is generated instead. If both the low and high
    # values are unlimited - '*..*' - then we do not generate a filter; the
    # range is unlimited.
    #
    # You can also use the shortcut notation when expressing unlimited ranges.
    # '>42' and '42..*' are equivalent. '<100' and '*..100' are equivalent as
    # well.
    #
    # Use a DateRangeFilter instead for date fields. It understands more date
    # forms.
    #
    # Please read the ElasticSearch documentation for more information:
    # https://www.elastic.co/guide/en/elasticsearch/reference/master/query-dsl-range-query.html
    class RangeFilter < ::Search::Filter

      InvalidRange = Class.new StandardError

      # Internal: The regex used to determine whether a term is a range
      # expression or not. A range expression takes one of two forms:
      #
      # * comparator value
      # * from..to
      #
      # Where comparator is one of >, <, <=, or >=. Value, from, and to should
      # be valid date expressions.
      #
      # For now this is identical to the RangeFilter regex.
      RANGE_EXPRESSION = %r{
        ([<>]=?)\s*(\S+)        # optional comparator followed by single value
        |                       # OR
        (\S+)\s*\.\.\.?\s*(\S+) # from .. to
      }x unless defined?(RANGE_EXPRESSION)

      # Create a new RangeFilter instance.
      def initialize(opts = {})
        super(opts)
        map_bool_collection
      end

      def execution
        options.fetch(:execution, :plain)
      end

      # Generate a filter hash from the given values.
      #
      # values - The range filter values as an Array of Strings.
      #
      # Returns a filter document Hash or nil.
      def build(values)
        return if values.blank?
        return values.first if values.length == 1
        return values if execution == :and || execution == :or
        { bool: { should: values } }
      end

      # Internal: Convert the values provided to the filter into range hashes
      # and validate the contents of those hashes.
      #
      # Returns this filter's BoolCollection.
      def map_bool_collection
        return bool_collection if defined? @mapped
        @mapped = true

        bool_collection.uniq!
        bool_collection.map_all! { |value| range_filter_for value unless value.nil? }
        bool_collection.intersect!

      rescue InvalidRange => err
        @valid = false
        @invalid_reason = err.message
        bool_collection
      end

      # Internal: Generate a range filter document hash from the value
      # String. If the value matches a range expression, then a range filter
      # document is returned. If the value does not match a range expression
      # then a term filter document is returned.
      #
      # A range expression looks like the following:
      #
      # * '> 20' or '>= 20'
      # * '< 2012-01-01' or '<= 2012-01-01'
      # * '10..20' or '10..*' or '*..20'
      #
      # The values can be any alphanumeric character. Only the range symbols
      # are treated specially.
      #
      # value - The range filter value as a String.
      #
      # Returns a filter document Hash or nil.
      def range_filter_for(value)
        value = value.to_s.strip
        match = RANGE_EXPRESSION.match(value)

        if match
          range_filter_hash(*match.captures)
        else
          range_filter_value(value)
        end
      end

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

        case comparator
        when ">";  hash[:gt]  = value
        when ">="; hash[:gte] = value
        when "<";  hash[:lt]  = value
        when "<="; hash[:lte] = value
        else
          hash[:gte] = from if from != "*"
          hash[:lte] = to   if to != "*"
        end

        validate_range_hash(hash)

        { range: { field => hash } } if hash.present?
      end

      # Internal: If the range expression is a single value, then fall back to
      # this method to try and generate a term filter.
      #
      # value - The single value
      #
      # Returns nil or a filter Hash.
      def range_filter_value(value)
        return if value.nil?
        validate_value(value)

        build_term_filter(field, value)
      end

      # Internal: Validate the range hash. If it contains a lower bound and an
      # upper bound, then assert that the lower bound is less than (or equal
      # to) the upper bound.
      #
      # hash - A range filter Hash.
      #
      # Returns nil.
      # Raises an InvalidRange exception if the range Hash is invalid.
      def validate_range_hash(hash)
        lower = hash.key?(:gte) ? hash[:gte] : hash[:gt]
        upper = hash.key?(:lte) ? hash[:lte] : hash[:lt]

        validate_value(lower) unless lower.nil?
        validate_value(upper) unless upper.nil?

        if !lower.nil? && !upper.nil? && try_numeric(lower) > try_numeric(upper)
          raise InvalidRange, "the lower bound of the range (#{lower} .. #{upper}) is greater than the upper bound"
        end

        nil
      end

      # Internal: No-op implementation.
      #
      # Raises an InvalidRange exception if the value is invalid.
      def validate_value(value)
        unless try_numeric(value).is_a? Numeric
          raise InvalidRange, "\"#{value}\" is not a numeric value - please provide an integer value"
        end
      end

      # Internal: Try to convert the string to a numeric value. If successful
      # then we return the numeric value. Otherwise we just return the input
      # string.
      #
      # str - A String.
      #
      # Returns the original string or a numeric.
      def try_numeric(str)
        Integer(str) rescue Float(str) rescue str
      end

    end  # RangeFilter
  end  # Filters
end  # Search
