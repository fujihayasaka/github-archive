# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # The purpose of the BoolFilter is to take a collection of other Filter
    # objects and construct an ES bool filter hash. The `must`, `must_not`,
    # and `should` components of the Filters are used to build up the ES bool
    # filter.
    class BoolFilter

      attr_reader :filters

      # Construct a new BoolFilter.
      #
      # filterish - A Filter or collection of filters
      # except    - Filters to exclude by name when `filterish` is a Hash
      #
      def initialize(filterish = nil, except = nil)
        @filters = []
        add_filters(filterish, except) if filterish
      end

      # Add a Filter to this bool filter. An ES bool filter hash will be
      # constructed from the Filter's `must`, `must_not`, and `should` ES
      # filters.
      #
      # filterish - A Filter or collection of filters
      # except    - Filters to exclude by name when `filterish` is a Hash
      #
      # Returns this bool filter instance.
      def add_filters(filterish, except = nil)
        case filterish
        when ::Search::Filter
          @filters << filterish

        when Array
          @filters.concat filterish

        when Hash
          except = Array(except) if except
          filterish.each do |name, filter|
            next if except && except.include?(name)
            @filters << filter
          end
        end

        @filters.compact!
        self
      end

      # Construct the ES bool filter hash from the provided Filter objects.
      #
      # Returns an ES bool filter hash.
      def build
        hash = {}

        hash[:must]     = select_filters { |filter| filter.must }
        hash[:must_not] = select_filters { |filter| filter.must_not }
        hash[:should]   = select_filters { |filter| filter.should }

        hash.delete_if { |_key, val| val.nil? }

        { bool: hash } unless hash.empty?
      end

      # Internal: Helper method that will iterate over the filters yielding
      # each to the given block. This method returns an Array of ES filter
      # hashes computed from each filter yielded to the block. If the array
      # contains only one filter, then it is returned. Nil is returned in the
      # array is empty.
      #
      # Returns nil or the ES filter hashes.
      def select_filters(&block)
        ary = @filters.map(&block)
        ary.flatten!
        ary.compact!

        case ary.length
        when 0; nil
        when 1; ary.first
        else ary
        end
      end
    end
  end
end
