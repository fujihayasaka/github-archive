# typed: true
# frozen_string_literal: true

module Repos
  module Advisories
    class SearchComponent < GitHub::FilterInputComponent
      def initialize(query: "", state: nil)
        hidden_inputs = {}
        hidden_inputs[:state] = state if state.present?

        super(
          tag_name: "repository-advisories-filter",
          icon: :search,
          method: :get,
          path: "?",
          use_pjax: false,
          turbo_frame: "_self",
          placeholder: "Filter advisories: severity:critical, ecosystem:npm, sort:newest",
          default_value: "",
          query: query || "",
          query_parameter_key: "query",
          suggestable_items: suggestable_items,
          form_test_selector: "advisories-search-form",
          input_test_selector: "advisories-search-field",
          reset_button_test_selector: "advisories-search-reset",
          hidden_inputs: hidden_inputs,
          my: 0,
          mb: 3,
        )
      end

      private

      def suggestable_items
        {
          severity: {
            description: "critical, high, moderate, low",
            suggestions: [
              { value: "critical" },
              { value: "high" },
              { value: "moderate" },
              { value: "low" },
            ],
          },
          ecosystem: {
            description: "npm, pip, rubygems, maven, nuget, composer, go, rust, pub, swift, actions",
            suggestions: [
              { value: "npm" },
              { value: "pip" },
              { value: "rubygems" },
              { value: "maven" },
              { value: "nuget" },
              { value: "composer" },
              { value: "go" },
              { value: "rust" },
              { value: "pub" },
              { value: "swift" },
              { value: "actions" },
            ],
          },
          package: {
            description: "filter by package name",
            suggestions: [],
          },
          sort: {
            description: "newest, oldest, severity",
            suggestions: [
              { value: "newest" },
              { value: "oldest" },
              { value: "severity" },
            ],
          },
        }
      end
    end
  end
end
