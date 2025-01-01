# typed: true
# frozen_string_literal: true

module Search
  module Filters
    # The ActionFilter is used to determine if a query is valid by checking
    # each value against a known blacklist.
    class ActionFilter < TermFilter

      # Create a new ActionFilter.
      #
      # options - The options Hash
      #   :denylist - The Array of actions that should mark the query as
      #                invalid if terms match.
      #
      def initialize(options = {})
        super(options)

        if options[:blacklist]
          ActiveSupport.deprecator.warn("ActionFilter's blacklist argument has been renamed to denylist")
        end

        @denylist = options.fetch(:denylist, nil)

        bool_collection
      end

      # Internal: Create the boolean collection that will be used by the
      # action filter. If any of the terms match the denylist, the query will
      # be marked as invalid.
      #
      # Returns this filter's BoolCollection.
      def bool_collection
        return @validated_collection if defined? @validated_collection
        @validated_collection = super

        if @validated_collection.must.empty?
          @valid = false
        end

        if @denylist.present?
          invalid_must = @denylist & Array(@validated_collection.must)
          invalid_should = @denylist & Array(@validated_collection.should)

          if invalid_must.any? || invalid_should.any?
            @valid = false
          end
        end

        @validated_collection
      end
    end
  end
end
