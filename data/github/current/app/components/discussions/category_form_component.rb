# typed: true
# frozen_string_literal: true

module Discussions
  class CategoryFormComponent < ApplicationComponent
    extend T::Sig

    sig do
      params(
        repository: Repository,
        viewer_can_create_announcements: T::Boolean,
        org_param: T.nilable(String),
        category: T.nilable(DiscussionCategory)
      ).void
    end
    def initialize(repository:, viewer_can_create_announcements:, org_param: nil, category: nil)
      @category = category || DiscussionCategory.new(repository: repository)
      @repository = repository
      @viewer_can_create_announcements = viewer_can_create_announcements
      @org_param = org_param
    end

    private

    attr_reader :category, :repository, :viewer_can_create_announcements
    alias :viewer_can_create_announcements? :viewer_can_create_announcements

    memoize def current_emoji_html
      category.emoji_html
    end

    def new?
      category.new_record?
    end

    def form_action
      if new?
        categories_path(user_id: @repository.owner_display_login, repository: @repository)
      else
        category_path(user_id: @repository.owner_display_login, repository: @repository, id: category.id)
      end
    end

    def form_method
      new? ? :post : :put
    end

    def submit_text
      new? ? "Create" : "Save changes"
    end

    def emoji_picker_path
      emoji_picker_categories_path(
        user_id: @repository.owner_display_login,
        repository: @repository,
        emoji: category.emoji,
      )
    end

    def cancel_path
      agnostic_categories_path(repository: @repository, org_param: @org_param)
    end
  end
end
