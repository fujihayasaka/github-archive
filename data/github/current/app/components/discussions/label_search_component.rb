# typed: true
# frozen_string_literal: true

module Discussions
  class LabelSearchComponent < ApplicationComponent
    def initialize(repository:, query:, can_edit_labels:)
      @repository = repository
      @query = query
      @can_edit_labels = fetch_or_fallback([true, false], can_edit_labels, false)
    end

    private

    def render?
      @repository.present?
    end

    def menu_content_path
      search_menu_discussions_labels_path(
        user_id: @repository.owner_display_login,
        repository: @repository.name,
        discussions_q: @query,
        org: params[:org]
      )
    end

    def edit_labels_path
      issues_labels_path(@repository.owner_display_login, @repository.name)
    end

    def can_edit_labels?
      @can_edit_labels
    end
  end
end
