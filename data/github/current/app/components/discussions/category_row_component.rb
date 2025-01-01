# typed: strict
# frozen_string_literal: true

module Discussions
  class CategoryRowComponent < ApplicationComponent
    extend T::Sig

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        category: DiscussionCategory,
        repository: Repository,
        categories: T::Enumerable[DiscussionCategory],
        editable_by_viewer: T::Boolean,
        deletable_by_viewer: T::Boolean,
        viewer_can_create_announcements: T::Boolean,
        org_param: T.nilable(String)
      ).void
    end
    def initialize(
      category:,
      repository:,
      categories:,
      editable_by_viewer:,
      deletable_by_viewer:,
      viewer_can_create_announcements:,
      org_param: nil
    )
      @category = category
      @repository = repository
      @categories = categories
      @editable_by_viewer = editable_by_viewer
      @deletable_by_viewer = deletable_by_viewer
      @viewer_can_create_announcements = viewer_can_create_announcements
      @org_param = org_param
    end

    private

    sig { returns(DiscussionCategory) }
    attr_reader :category

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(T::Enumerable[DiscussionCategory]) }
    attr_reader :categories

    sig { returns(T::Boolean) }
    attr_reader :editable_by_viewer

    sig { returns(T::Boolean) }
    attr_reader :deletable_by_viewer

    sig { returns(T::Boolean) }
    attr_reader :viewer_can_create_announcements

    sig { returns(T.nilable(String)) }
    attr_reader :org_param

    alias :editable? :editable_by_viewer
    alias :viewer_can_create_announcements? :viewer_can_create_announcements

    sig { returns(String) }
    def category_edit_path
      if org_param.present?
        edit_org_discussions_category_path(org: org_param, id: category.id)
      else
        edit_category_path(repository.owner_display_login, repository, id: category.id)
      end
    end

    sig { returns(T::Boolean) }
    def deletable?
      return false unless deletable_by_viewer
      categories.count > 1
    end

    sig { returns(String) }
    def category_edit_button_text
      "Edit #{self.category.name} category"
    end
  end
end
