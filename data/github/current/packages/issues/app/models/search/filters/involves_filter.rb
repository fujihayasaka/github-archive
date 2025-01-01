# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # This filter name is a slight misnomer, but it was born out of wanting to
    # search all issues that a user is involved with somehow. We do this by
    # creating a user filter across several fields on an issue: author,
    # assignee, mention, commentor. This filter should match one of these
    # fields in order to select that document.
    #
    # The fields to search are not set in stone. Pass in an array of :field
    # names that you want to search.
    class InvolvesFilter < UserFilter

      def must
        filter = build(bool_collection.must)

        if filter.is_a? Array
          { bool: { should: filter } }
        else
          filter
        end
      end

      def must_not
        build(bool_collection.must_not)
      end

      def build(values)
        return if values.blank?
        values = values.first if singular?

        ary = Array(field).map do |current_field|
          build_term_filter(current_field, values, execution: execution)
        end
        ary.compact!

        case ary.length
        when 0; nil
        when 1; ary.first
        else ary
        end
      end

    end  # InvolvesFilter
  end  # Filters
end  # Search
