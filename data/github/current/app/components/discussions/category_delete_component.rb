# typed: true
# frozen_string_literal: true

module Discussions
  class CategoryDeleteComponent < ApplicationComponent
    extend T::Sig

    def initialize(category:, repository:, categories:)
      @category = category
      @repository = repository
      @categories = categories
    end

    private

    attr_reader :category, :repository, :categories

    def path_for_category_delete
      category_path(
        user_id: repository.owner_display_login,
        repository: repository,
        id: category.id,
      )
    end

    def reassignment_categories
      categories
        .reject { |c| c == category || (!category.supports_polls? && c.supports_polls?) }
        .collect { |c| [c.name, c.id] }
    end

    sig { returns(String) }
    def category_delete_button_text
      "Delete #{category.name} category"
    end
  end
end
