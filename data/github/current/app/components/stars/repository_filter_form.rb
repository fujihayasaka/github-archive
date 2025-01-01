# typed: true
# frozen_string_literal: true

class Stars::RepositoryFilterForm < ApplicationForm
  form do |repo_filter_form|
    repo_filter_form.group(layout: :horizontal) do |search_group|
      search_group.text_field(
        name: "q",
        label: "Search",
        visually_hide_label: true,
        placeholder: @placeholder,
        aria: { label: @placeholder },
        value: @phrase,
        type: "search",
        full_width: true,
        autocapitalize: "off",
        autocomplete: "off",
        leading_visual: { icon: :search },
        color: :muted,
        data: { test_selector: "stars-repo-filter" }
      )

      search_group.hidden(name: "tab", value: "stars")
      search_group.hidden(name: "type", value: @params[:type])
      search_group.hidden(name: "sort", value: @params[:sort])
      search_group.hidden(name: "direction", value: @params[:direction])

      search_group.submit(label: "Search", name: :submit)
    end
  end

  def initialize(params:, phrase:, placeholder:)
    @params = params
    @phrase = phrase
    @placeholder = placeholder
  end
end
