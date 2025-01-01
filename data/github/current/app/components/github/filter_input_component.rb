# typed: true
# frozen_string_literal: true

module GitHub
  # THIS COMPONENT IS DEPRECATED
  # Use Primer's QueryBuilder component instead.
  # ---------------------------------------------
  #
  # This class provides a reusable component that allows for an easier time
  # wiring in suggestable filters.
  #
  # = How to use this component
  #
  # == TypeScript
  #
  # Make sure you have created a TypeScript file in `app/assets/modules/github` (or a subfolder)
  # that includes a class inheriting from BaseFilterElement (see filter-input.ts), and implementing
  # that class's abstract method. This class should be annotated with @controller - it sets up a
  # Catalyst controller that will be in charge of modifying the search bar suggestions.
  #
  # For more detailed instructions, look at the comments in filter-input.ts as they explain
  # the various functions and what they do. If you want a more in depth explanation of Catalyst
  # and how it works, check out the docs here: https://github.github.io/catalyst/guide/introduction/
  #
  # Next create or modify a TypeScript file in the the directory `app/assets/modules`
  # that imports the TypeScript file you created. This file should then be included
  # in the template of the page that will use this component by adding:
  #
  # ```
  # <% content_for :scripts do %>
  #   <%= javascript_bundle "file-name" %>
  # <% end %>
  # ```
  # Where `file-name` is the name of the TypeScript file you created (without extension).
  # Typically this second file will be used to import all feature-related scripts that your
  # page needs. This allows you to split your TypeScript up into multiple files, whilst retaining
  # the simplicity of a single file to include on the page.
  #
  # == Defining suggestions
  #
  # You simply need pass your suggestions as the suggestable_items argument and they
  # will be suggested appropriately. Both inline suggestions and dynamic lookup are
  # supported:
  #
  # ```
  # suggestable_items: {
  #   repo_risks: {
  #     description: "high, medium, low, clear, unknown",
  #     suggestions: [
  #       { value: 'high', description: 'High Risk Repos' },
  #       { value: 'medium', description: 'Medium Risk Repos' },
  #       { value: 'low', description: 'Low Risk Repos' }
  #     ]
  #   },
  #   branches: {
  #     description: "filter by branch",
  #     path: "/some/feature/branches-path"
  #   }
  # }
  # ```
  #
  # If a path is provided, a GET request will be made to that path to retrieve
  # suggestions. The result will be cached. The code expects to receive JSON in
  # the following format:
  # [
  #   {
  #     value: 'value',
  #     description: 'description',
  #     isAlpha: true/false,
  #     isBeta: true/false,
  #   },
  #   ...
  # ]
  # Only the value key is required; all others can be omitted.
  #
  # If you have qualifiers that support negation (e.g. `-repo:reponame`) and would like
  # the component to provide suggestions for the negated qualifier, you will need to
  # add a `negatable` key set to true to the qualifier hash in your suggestable_items hash:
  # ```
  # suggestable_items: {
  #   repo_risks: {
  #     negatable: true,
  #     description: "high, medium, low, clear, unknown",
  #     suggestions: [
  #      ...
  #     ]
  #   }
  # }
  # ```
  #
  # default_value is the value which is put into the search box when
  # the search is cleared. For most filters, this will be an empty string,
  # so the parameter need not be passed.
  class FilterInputComponent < ApplicationComponent
    def initialize(
      tag_name:,
      icon: :search,
      method: :get,
      path: "?",
      use_pjax: false,
      turbo_frame: nil,
      placeholder: "Search",
      query: "",
      query_parameter_key: "query",
      suggestable_items: {},
      default_value: "",
      use_compact_clear_button: false,
      verbose_clear_button_text: "Clear current search query, filters, and sorts",
      my: 3,
      form_test_selector: nil,
      input_test_selector: nil,
      reset_button_test_selector: nil,
      hidden_inputs: {},
      **system_arguments
    )
      @system_arguments = system_arguments
      @tag_name = tag_name
      @icon = icon
      @method = method
      @path = path
      @use_pjax = use_pjax
      @turbo_frame = turbo_frame
      @placeholder = placeholder
      @query = query.present? ? "#{query.strip} " : ""
      @query_parameter_key = query_parameter_key
      @suggestable_items = suggestable_items
      @default_value = default_value.present? ? "#{default_value.strip} " : ""
      @use_compact_clear_button = use_compact_clear_button
      @verbose_clear_button_text = verbose_clear_button_text
      @my = my
      @form_test_selector = form_test_selector || "#{@tag_name}-search"
      @input_test_selector = input_test_selector || "#{@tag_name}-search-box"
      @reset_button_test_selector = reset_button_test_selector || "#{@tag_name}-reset-button"
      @hidden_inputs = hidden_inputs
    end

    memoize def suggestable_qualifiers
      @suggestable_items.map do |key, value|
        qualifier = { value: "#{key}:"  }
        qualifier[:description] = value[:description] if value.has_key?(:description)
        qualifier[:isNew] = true if value[:is_new]
        qualifier
      end
    end

    memoize def negatable_qualifiers
      @suggestable_items.map do |key, value|
        key if value[:negatable]
      end.compact
    end

    # Suggestable items may be a list of pre-defined items: [:suggestions]
    # Or a path to call with AJAX to get items: [:path]
    memoize def suggestable_items_json
      @suggestable_items.map do |key, value|
        if value.has_key?(:path)
          ["data-suggestable-#{key}-path", value[:path]]
        else
          ["data-suggestable-#{key}", (value[:suggestions] || []).to_json]
        end
      end
    end

    def hide_clear_button?
      @default_value.strip.split(" ").sort == @query.strip.split(" ").sort
    end
  end
end
