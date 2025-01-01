# typed: true
# frozen_string_literal: true

module Search
  module Filters

    class OrFilter < ::Search::Filter

      attr_reader :filters

      # Construct a new BoolFilter.
      #
      # filterish - A Filter or collection of filters
      # except    - Filters to exclude by name when `filterish` is a Hash
      #
      def initialize(filterish = nil, except = nil)
        @valid = true
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

      # Return `true` if this filter is empty. Recursively checks all the
      # filters it contains.
      def blank?
        return true if @filters.empty?
        @filters.all?(&:blank?)
      end

      # Returns a filter Hash that can be used in the `must` portion of an ES
      # boolean filter. Since this is an OR filter, we take the must clauses
      # aof the component filters and wrap them in a `bool` should filter.
      def must
        val = select_filters { |filter| filter.must }

        if val.instance_of? Array
          { bool: { should: val } }
        else
          val
        end
      end

      # Returns a filter Hash that can be used in the `must_not` portion of an
      # ES boolean filter.
      def must_not
        select_filters { |filter| filter.must_not }
      end

      # Returns a filter Hash that can be used in the `should` portion of an
      # ES boolean filter.
      def should
        select_filters { |filter| filter.should }
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
