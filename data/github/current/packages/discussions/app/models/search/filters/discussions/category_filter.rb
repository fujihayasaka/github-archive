# typed: true
# frozen_string_literal: true

module Search
  module Filters
    module Discussions
      # Public: The CategoryFilter is used to limit discussion search results to a
      # particular category or collection of categories. This class
      # encapsulates the logic of looking up categories and generating
      # ElasticSearch term filters.
      class CategoryFilter < TermFilter
        # Create a new CategoryFilter.
        #
        # opts - The options Hash
        #   :field - the document field containing the category IDs
        #   :repostory_ids - the repository IDs that this category filter should be scoped to
        sig { params(opts: T.untyped).void }
        def initialize(opts = {})
          super(opts)

          @field ||= :category_id
          @repository_ids = opts[:repository_ids]

          map_bool_collection
        end

        # Public: This reason can be used when the category filter is invalid.
        sig { returns(T.untyped) }
        def invalid_reason
          "The listed categories cannot be searched because the categories do not exist."
        end

        # Internal: Take the boolean collection and convert all the values into
        # category IDs if possible.
        #
        # Returns this filter's boolean collection.
        sig { returns(T.untyped) }
        def map_bool_collection
          return bool_collection if defined? @mapped
          @mapped = true

          # save these off for our validity check
          must_flag = bool_collection.must?
          must_not_flag = bool_collection.must_not?

          ids_by_name = category_names
          bool_collection.flatmap_all! { |category_name| ids_by_name.fetch(category_name.downcase, []) }

          bool_collection.uniq!

          # did we specify invalid category IDs?
          @valid = (must_flag == bool_collection.must?) &&
            (must_not_flag == bool_collection.must_not?)

          # prune `must_not` repository IDs from the `must` and `should` lists
          bool_collection.intersect!
          bool_collection
        end

        # Internal: Convert the `category.name` strings from the boolean
        # collection into category IDs.
        #
        # Note that a single name may map to multiple IDs if we have more than
        # one repository to search.
        #
        # Returns a Hash mapping category names to an array of IDs.
        sig { returns(T.untyped) }
        def category_names
          names = bool_collection.all

          if names.empty?
            {}
          else
            DiscussionCategory
              .where(name: names, repository_id: @repository_ids)
              .pluck(:name, :id)
              .map { |name, id| [name.force_encoding("UTF-8").downcase, id] }
              .group_by(&:first)
              .transform_values { |pairs| pairs.map(&:second) }
          end
        end
      end  # CategoryFilter
    end # Discussions
  end  # Filters
end  # Search
