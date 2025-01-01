# typed: true
# frozen_string_literal: true

module Search
  module Filters
    class IdsToExcludeFilter < ::Search::Filter
      def initialize(opts = {})
        super(opts)

        @field = :issue_id
        @ids_to_exclude = opts[:ids_to_exclude]
      end

      # Override unnecessary methods of superclass to be no-ops.
      def build(values); end
      def must; end
      def should; end

      # This filter is only used when needed, so it will never be blank.
      def blank?
        false
      end

      # Implement the only filter we actually need.
      def must_not
        build_term_filter(@field, bool_collection.must_not)
      end

      # Builds up the exclusion clause for issues referenced in a given memex.
      def bool_collection
        return @bool_collection if defined? @bool_collection

        @bool_collection = ::Search::ParsedQuery::BoolCollection.new
        @bool_collection.must_not(@ids_to_exclude)
        @bool_collection.must_not.uniq! if @bool_collection.must_not?

        @bool_collection
      end
    end
  end
end
