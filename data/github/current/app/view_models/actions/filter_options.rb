# typed: true
# frozen_string_literal: true

class Actions::FilterOptions
  attr_reader :search_query, :category_slug, :include_preview_templates

  def initialize(search_query: nil, category_slug: nil, include_preview_templates: nil)
    @search_query = CGI.unescape(search_query || "")
    @category_slug = category_slug || ""
    @include_preview_templates = include_preview_templates || false
  end

  def as_params(overrides = {})
    {
      query: search_query,
      category: category_slug
    }.merge(overrides).compact_blank
  end
end
