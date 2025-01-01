# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # A close_reference filter is used to limit search results to issues
    # or pull_requests that have a close_issue_reference record.
    # This is represented in ES with :has_closing_reference boolean.
    class CloseReferenceFilter < ::Search::Filter
      MUST_NOT_EXIST = [Search::Filter::NONE, Search::Filter::MISSING, Search::Filter::NO]
      MUST_EXIST     = [Search::Filter::EXISTS, Search::Filter::WILDCARD, Search::Filter::ANY]

      attr_writer :bool_collection

      # Create a new CloseReferenceFilter.
      #
      # opts - The options Hash
      #
      def initialize(opts = {})
        super(opts)

        if qualifiers.include?(:linked)
          musts = qualifiers[:linked].must
          must_nots = qualifiers[:linked].must_not
          populate_bool_collection(musts, negated: false)
          populate_bool_collection(must_nots, negated: true)
        end
      end

      def bool_collection
        @bool_collection ||= Search::ParsedQuery::BoolCollection.new :milestone
      end

      # Just no-op to keep this simple (filter is built once at instantiation)
      def build(values)
        values
      end

      # Only one filter clause per type (must, must_not, should) for milestone
      def must
        bool_collection.must.try(:first)
      end

      # Only one filter clause per type (must, must_not, should) for milestone
      def must_not
        bool_collection.must_not.try(:first)
      end

      # Only one filter clause per type (must, must_not, should) for milestone
      def should
        bool_collection.should.try(:first)
      end

      # Internal: Build a filter Hash from the given set of values, store in
      # filter's bool_collection for extraction by callers via must/must_not,should methods
      #
      # quals - The Array of values (from must/must_not/should of milestone qualifiers)
      #
      # NOTE: to mimic current filter behavior, we're assuming all these clauses will
      # land in the "must" branch of a parent Bool filter.
      def populate_bool_collection(quals, negated:)
        return if quals.blank?

        if quals.select { |v| MUST_EXIST.include?(v) }.any?
          # ES term filters don't accept wildcards, so use exists clause for "milestone:*"
          # and "milestone:any" - see also: https://github.com/github/github/issues/83316
          bool_collection.must({ exists: { field: :milestone_num } })

        elsif quals.select { |v| MUST_NOT_EXIST.include?(v) }.any?
          # "milestone:none" should behave same as "no:milestone"
          bool_collection.must({ bool: { must_not: { exists: { field: :milestone_num } } } })

        else
          # otherwise, just simple KV term filter on human-readable milestone name
          # if matching on milestone name, route stuff from must_not into our must output for reasons
          if negated
            bool_collection.must({ bool: { must_not: { term: { milestone_title: quals.first.downcase } } } }) if quals.first
          else
            bool_collection.must({ term: { milestone_title: quals.first.downcase } }) if quals.first
          end
        end
      end
    end
  end
end
