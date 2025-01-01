# typed: true
# frozen_string_literal: true

class Memex::ProjectList::SearchForm < ApplicationForm
  form do |search|
    search.text_field(
      name: :query,
      leading_visual: {
        icon: :search
      },
      full_width: true,
      label: "Search all projects",
      show_clear_button: true,
      id: "project-search-input",
      visually_hide_label: true,
      clear_button_id: "clear-project-search-button",
      value: @parsed_query.stringify + " ",
      placeholder: "Search all projects",
      "aria-label": "Search all projects"
    )

    if @context == User
      search.hidden(
        label: "",
        name: :tab,
        value: "projects"
      )
    end

    search.hidden(
      label: "",
      name: :is_search,
      value: true,
      data: { test_selector: "project-is-search-param" }
    )
  end

  def initialize(context:, parsed_query:)
    @context = context
    @parsed_query = parsed_query
  end
end
