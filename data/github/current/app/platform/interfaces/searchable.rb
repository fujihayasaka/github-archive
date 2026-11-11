# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Searchable
      extend T::Helpers
      include ::Platform::Interfaces::Base
      include ::Platform::Helpers::SearchHelper

      requires_ancestor { GraphQL::Schema::Object }

      description "Entities that can be searched."
      visibility :internal


      field :search, Connections::SearchResultItem, description: "Perform a search across resources, returning a maximum of 1,000 results.", null: false, connection: true do
        argument :query, String, "The search string to look for. GitHub search syntax is supported. For more information, see \"[Searching on GitHub](https://docs.github.com/search-github/searching-on-github),\" \"[Understanding the search syntax](https://docs.github.com/search-github/getting-started-with-searching-on-github/understanding-the-search-syntax),\" and \"[Sorting search results](https://docs.github.com/search-github/getting-started-with-searching-on-github/sorting-search-results).\"", required: true
        argument :type, Enums::SearchType, "The types of search items to search within.", required: true
        argument :aggregations, Boolean, "Calculate aggregations. This arg must be true for `languageAggregations` to be returned.", default_value: false, visibility: :internal, required: false
        argument :skip, Integer, "The number of items to skip, for pagination.", required: false, visibility: :internal
      end
    end
  end
end
