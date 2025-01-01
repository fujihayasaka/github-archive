# typed: true
# frozen_string_literal: true

module Search
  module Filters
    class StarSearchFilter < ::Search::Filter
      class StarSearchFilterError < StandardError; end

      attr_reader :user, :field

      # Create a new StarSearchFilter.
      #
      # opts - The options Hash
      #   :star_user - The currently logged in User
      #
      def initialize(opts = {})
        super(opts)

        @field = options.fetch(:field, :repo_id)

        # A Star search without a user makes no sense.
        if !(@star_user = options.fetch(:star_user, nil))
          raise StarSearchFilterError, "Cannot filter stars without a user specifed"
        end
      end

      def blank?
        false
      end

      def must
        build_term_filter(field, bool_collection.must) if bool_collection.must?
      end

      # should and must_not is not applicable to stars, must explains it all
      def must_not; end
      def should; end

      # NOOP/Identity `map_bool_collection` and `build` as in `RepositoryFilter`
      # since both filters are filtering by lists of Repository ids
      def build(values); end

      def map_bool_collection
        bool_collection
      end

      def bool_collection
        return @bool_collection if defined? @bool_collection
        @bool_collection = ::Search::ParsedQuery::BoolCollection.new

        ids = repository_ids
        @bool_collection.must(ids)

        @bool_collection
      end

      # Internal: Perform a SQL query to retrieve the starred repository IDs
      # to filter by.
      #
      # Returns an Array of repository IDs
      def repository_ids
        return @repository_ids if defined? @repository_ids

        starred_repo_ids = @star_user.stars.repositories.pluck(:starrable_id)
        @repository_ids = Repository.active.where(id: starred_repo_ids).pluck(:id)
      end
    end
  end
end
