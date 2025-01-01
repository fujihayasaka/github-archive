# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class SearchResultItem < Edges::Base
      description "An edge in a connection."

      node_type Unions::SearchResultItem

      field :text_matches, [Objects::TextMatch, null: true], description: "Text matches on the result found.", null: true

      def text_matches
        highlights = @object.highlights || {}

        # Some properties get returned twice, once with an ES suffix,
        # and some properties only get returned once with an ES suffix.
        # This block renames properties with an ES suffix, and merges the results
        # with the properly named property if it exists.

        property_normalizer_regex = /\.(ngram|plain)\z/
        highlights.clone.each do |property, _matches|
          if property.match(property_normalizer_regex)
            correct_key = property.gsub(property_normalizer_regex, "")

            if highlights[correct_key]
              highlights[correct_key].concat(highlights[property])
              highlights[correct_key].uniq!
            else
              highlights[correct_key] = highlights[property]
            end

            highlights.delete(property)
          end
        end

        highlights.map do |property, matches|
          matches.map do |fragment_match|
            Platform::Models::TextMatch.new(property: property, fragment: fragment_match[:text], indices: fragment_match[:indices])
          end
        end.flatten
      end
    end
  end
end
