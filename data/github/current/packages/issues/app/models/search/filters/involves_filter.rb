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

      # We can't use the TermFilter's `should` directly,
      # because when the execution option is set to `:and`,
      # the filter components are joined by `and` conditions which gives us the wrong result.
      def should
        if !FeatureFlag.vexi.enabled_or_raise?(:copilot_involves_filter_kill_switch) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          and_should = bool_collection.and_should
          if execution == :and && and_should.present?
            return build_and_should_filter(and_should)
          end

          return build(bool_collection.and_should) if and_should.present?
        end

        super
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

      def build_and_should_filter(and_should)
        {
          bool: {
            should: Array(field).map do |current_field|
              and_should.map do |values|
                {
                  bool: {
                    should: {
                      terms: { current_field => values }
                    }
                  }
                }
              end
            end.flatten.compact
          }
        }
      end

    end  # InvolvesFilter
  end  # Filters
end  # Search
