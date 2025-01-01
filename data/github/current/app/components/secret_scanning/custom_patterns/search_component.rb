# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    class SearchComponent < GitHub::FilterInputComponent
      def initialize(
        icon: :search,
        method: :get,
        path: "?",
        pjax: false,
        placeholder: "Narrow your search",
        query: ""
      )
        super(
          tag_name: "custom-patterns-filter",
          icon: icon,
          method: method,
          path: path,
          use_pjax: pjax,
          placeholder: placeholder,
          default_value: "is:published,unpublished",
          query: query,
          suggestable_items: suggestable_items,
          input_test_selector: "custom-patterns-filter-search-box",
        )
      end

      def suggestable_items
        items = {
          is: {
            description: "published | unpublished",
            suggestions: [
              { value: "published" },
              { value: "unpublished" },
            ]
          },
          sort: {
            description: suggestable_sorts.map { |sort| sort[:value] }.join(", "),
            suggestions: suggestable_sorts
          },
          "push-protection": {
            description: suggestable_push_protected_filter.map { |push_protected_option| push_protected_option[:value] }.join(", "),
            suggestions: suggestable_push_protected_filter
          }
        }
      end

      def suggestable_sorts
        ::Search::Queries::SecretScanning::CustomPatternsQuery::sort_options.map { |option| { value: option[:slug] } }
      end

      def suggestable_push_protected_filter
        ::Search::Queries::SecretScanning::CustomPatternsQuery::push_protected_filter_options.map { |option| { value: option[:slug] } }
      end
    end
  end
end
