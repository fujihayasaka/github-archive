# typed: true
# frozen_string_literal: true

module Stafftools
  class SimpleSearchFormComponent < ApplicationComponent
    attr_reader \
      :query_label,
      :form_url,
      :query_placeholder,
      :form_group_test_selector,
      :extra_input_fields

    # Public: Create a new SimpleSearchFormComponent
    #
    # This is a simple search form component for use within site admin views, which supports
    # submitting the `query` param to the provided URL to filter search results.
    #
    # form_url - Required String to use for the form action URL
    # query_label - Optional String to use for the label associated with the query input
    # query_placeholder - Optional String to use for the placeholder for the query input
    # form_group_test_selector - Optional String to use for the test_selector on the form group div
    # extra_input_fields - Optional Array of Hash, where each field Hash takes the form:
    #   {
    #     name: "my_field",
    #     id: "my_field",
    #     value: "important value"
    #     hidden: false,
    #   }
    #
    # Returns SimpleSearchFormComponent
    def initialize(
      form_url:,
      query_label: nil,
      query_placeholder: "",
      form_group_test_selector: nil,
      extra_input_fields: []
    )
      @query_label = query_label
      @form_url = form_url
      @query_placeholder = query_placeholder
      @form_group_test_selector = form_group_test_selector
      @extra_input_fields = extra_input_fields
    end
  end
end
