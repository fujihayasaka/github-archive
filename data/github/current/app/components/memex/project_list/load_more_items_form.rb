# typed: true
# frozen_string_literal: true

class Memex::ProjectList::LoadMoreItemsForm < ApplicationForm # rubocop:disable ViewComponent/ComponentsHaveUnitTests
  form do |load_more_items_form|
    load_more_items_form.hidden(
      label: "",
      name: :cursor,
      value: @cursor
    )

    load_more_items_form.hidden(
      label: "",
      name: :client_uid,
      value: "",
      class: "js-client-uid-field"
    )

    load_more_items_form.hidden(
      label: "",
      name: :query,
      value: @query
    )

    if @sort_query_cursor
      load_more_items_form.hidden(
        label: "",
        name: :sort_query_cursor,
        value: @sort_query_cursor
      )
    end

    load_more_items_form.submit(
      label: "Load more...",
      name: "",
      class: "flex-self-center",
      scheme: :link,
      data: { disable_with: "Loading more...", test_selector: "project-load-more-button" }
    )
  end

  def initialize(cursor:, query:, sort_query_cursor:)
    @cursor = cursor
    @query = query
    @sort_query_cursor = sort_query_cursor
  end
end
