# typed: true
# frozen_string_literal: true

module Discussions
  class CategoryIndexDescriptionComponent < ApplicationComponent
    def initialize(categories:, selected_category_slug:, current_repository:, hide_separator: false)
      @categories = categories
      @selected_category_slug = selected_category_slug
      @current_repository = current_repository
      @hide_separator = hide_separator
    end

    private

    attr_reader :categories, :selected_category_slug, :current_repository, :hide_separator

    memoize def selected_category
      categories.find { |category| category.slug == selected_category_slug }
    end

    def render_category_title?
      selected_category.present?
    end
  end
end
