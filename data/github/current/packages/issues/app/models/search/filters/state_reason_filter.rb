# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # A state_reason filter is used to limit search results to a particular
    # state_reason. `state_reason` field in order for this filter to be used.
    class StateReasonFilter < ::Search::Filter
      MUST_NOT_EXIST = [Search::Filter::NONE, Search::Filter::MISSING, Search::Filter::NO]
      MUST_EXIST     = [Search::Filter::EXISTS, Search::Filter::WILDCARD, Search::Filter::ANY]

      # Added as part of issues advanced search to allow multiple reasons to be ANDed together.
      # Before, only the :first reason would be considered in a query.
      attr_reader :accept_multiple_reasons

      attr_writer :bool_collection

      # Create a new StateReasonFilter.
      #
      # opts - The options Hash
      #
      def initialize(opts = {})
        super(opts)

        # false by default to maintain compatibility with the legacy search
        @accept_multiple_reasons = opts.fetch(:accept_multiple_reasons, false)

        if qualifiers.include?(:reason)
          musts = qualifiers[:reason].must
          must_nots = qualifiers[:reason].must_not
          shoulds = qualifiers[:reason].should
          must_state = qualifiers[:state]&.must
          must_not_state = qualifiers[:state]&.must_not

          if must_state && must_state.first
            state = must_state.first
          elsif must_not_state && must_not_state.first
            state = must_not_state.first == "closed" ? "open" : "closed"
          else
            state = "all"
          end

          populate_bool_collection(musts, state, negated: false)
          populate_bool_collection(must_nots, state, negated: true)
          populate_bool_collection(shoulds, state, negated: false)
        end
      end

      def execution
        options.fetch(:execution, :plain)
      end

      def bool_collection
        @bool_collection ||= Search::ParsedQuery::BoolCollection.new :reason
      end

      # Just no-op to keep this simple (filter is built once at instantiation)
      def build(values)
        values
      end

      def must
        if @accept_multiple_reasons
          bool_collection.must
        else
          bool_collection.must.try(:first)
        end
      end

      def must_not
        if @accept_multiple_reasons
          bool_collection.must_not
        else
          bool_collection.must_not.try(:first)
        end
      end

      def should
        if @accept_multiple_reasons
          bool_collection.should
        else
          bool_collection.should.try(:first)
        end
      end

      # Internal: Build a filter Hash from the given set of values, store in
      # filter's bool_collection for extraction by callers via must/must_not,should methods
      #
      # quals - The Array of values (from must/must_not/should of state reason qualifiers)
      #
      # NOTE: to mimic current filter behavior, we're assuming all these clauses will
      # land in the "must" branch of a parent Bool filter.
      def populate_bool_collection(quals, state, negated:)
        return if quals.blank? || !quals.first

        quals = [quals.first] unless @accept_multiple_reasons

        quals.each do |state_reason|
          is_completed = state_reason == "completed"
          query_fragment = {}

          if %w[closed all].include?(state) && is_completed
            if negated
              if state == "all"
                query_fragment = {
                  bool: {
                    should: [
                      {
                        exists: { field: "state_reason" },
                      }, {
                        term: { state: "open" }
                      }
                    ]
                  }
                }
              else
                # closed state
                query_fragment = { bool: { must: { exists: { field: "state_reason" } } } }
              end
            else
              # returns true for closed issues that have missing state_reason key in the document
              # OR state_reason: null
              query_fragment = {
                bool: {
                  must: {
                    term: {
                      state: "closed"
                    }
                  },
                  must_not: {
                    exists: {
                      field: "state_reason"
                    }
                  }
                }
              }
            end

          else
            if negated
              query_fragment = {
                bool: { must_not: { term: { state_reason: state_reason.parameterize.underscore } } }
              }
            else
              # this could be optimized since some search return surly no results so we could return early
              # eg. state:open with state_reason:completed
              query_fragment = { term: { state_reason: state_reason.parameterize.underscore } }
            end
          end

          next if query_fragment.empty?

          if execution == :or
            bool_collection.should(query_fragment)
          else
            bool_collection.must(query_fragment)
          end
        end
      end
    end
  end
end
