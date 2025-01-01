# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # The ProjectOwnerFilter is critical for ensuring that users only see the
    # private data that they are allowed to see.
    class ProjectOwnerFilter < ::Search::Filter

      attr_reader :owner_id, :owner_type

      # Create a new ProjectOwnerFilter.
      #
      # opts - The options Hash
      #   :owner_id - restrict the filter to a single owner
      #   :owner_type - user or org
      #
      def initialize(opts = {})
        super(opts)

        @owner_id = options.fetch(:owner_id, nil)
        @owner_type = options.fetch(:owner_type, nil)
        raise(ArgumentError, ":owner_id must not be nil") if @owner_id.nil?

        unless @owner_type && (@owner_type == "org" || @owner_type == "user")
          raise(ArgumentError, ":owner_type must not be 'org' or 'user")
        end

        bool_collection  # initialize our boolean collection
      end

      # Returns nil or a filter Hash.
      def must
        if @owner_type == "org"
          { term: { org_id: @owner_id } }
        elsif @owner_type == "user"
          { term: { user_id: @owner_id } }
        end
      end

      # Returns nil or a filter Hash.
      def must_not
        nil
      end

      # A `should` filter is not applicable to the project owner filter.
      #
      # Returns nil
      def should; end

      # This filter will never be blank.
      #
      # Returns false
      def blank?
        false
      end

      # Override the superclass method and make it into a noop.
      #
      # Returns nil
      def build(values); end

      # Internal: Create the boolean collection that will be used by the
      # project owner filter.
      #
      # Returns this filter's boolean collection.
      def bool_collection
        return @bool_collection if defined? @bool_collection
        @bool_collection = ::Search::ParsedQuery::BoolCollection.new

        @bool_collection.must owner_id

        @bool_collection
      end

      # Interal: Override the superclass method and make it a noop
      # implementation. Mapping the boolean collection is not applicable for
      # the project owner filter.
      #
      # Returns this filter's boolean collection.
      def map_bool_collection
        bool_collection
      end
    end  # ProjectOwnerFilter
  end  # Filters
end  # Search
