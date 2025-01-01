# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # The EnumeratedTermFilter is specifically here to extract out the
    # 'should' section of the `ParsedQuery` and turn it into something
    # ElasticSearch can use. Classes in the Search::Filter hierarchy share
    # the same `execution` option across their `should` and `must` values,
    # which doesn't work for us. Subclassing is simpler than trying to use the
    # `build_term_filter` method with the correct options.
    class EnumeratedTermFilter < ::Search::Filters::TermFilter

      # We can't use the TermFilter's `should` directly,
      # because the execution option is set to `:and`, which
      # gives us the wrong result.
      def should
        and_should = bool_collection.and_should
        # The and_should could've been negated by a must_not,
        # so we need to make sure the array is present
        return unless and_should && and_should.length > 0

        if and_should.length == 1
          { terms: { field => and_should[0] } }
        else
          if execution == :or
            { terms: { field => and_should.flatten } }
          else
            # in terms of labels, if we have > 1 and_should,
            # we need to express that as a `must`
            # `label:a,b label:c,d` means (a or b) and (c or d)
            nil
          end
        end
      end

      def must
        and_should = bool_collection.and_should

        base_filter = super

        return base_filter unless and_should && and_should.length > 1

        if base_filter.nil?
          # if base_filter is nil then bool_collection.must is nil,
          # so our and_should filter will be the whole `must`
          and_should_filter(and_should)
        elsif base_filter.is_a?(Array)
          # if base_filter is an array, we need to wrap it in a bool query and spread the base filter.
          { bool: { must: [
            *base_filter,
            and_should_filter(and_should)
          ] } }
        elsif base_filter[:term]
          # base is a term query. we need to wrap it in a bool query
          { bool: { must: [
            base_filter,
            and_should_filter(and_should)
          ] } }
        elsif base_filter[:bool]
          # base is a bool query. we need to append the and_should
          # filter
          base_filter[:bool][:must] << and_should_filter(and_should)
          base_filter
        end
      end

      def and_should_filter(and_should)
        # We want to skip the must: filter if we
        # know the execution type is :or
        if execution == :or
          nil
        else
          { bool: { must:
            and_should.map do |values|
              { bool: { should: { terms: { field => values } } } }
            end
          } }
        end

      end
    end # EnumeratedTermFilter
  end  # Filters
end  # Search
