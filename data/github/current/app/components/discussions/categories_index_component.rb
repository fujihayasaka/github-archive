# typed: true
# frozen_string_literal: true

module Discussions
  class CategoriesIndexComponent < ApplicationComponent
    extend T::Sig

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        repository: T.untyped,
        categories: T.untyped,
        sections: T.untyped,
        org_param: T.nilable(String)
      ).void
    end
    def initialize(repository:, categories:, sections:, org_param: nil)
      @repository = repository
      @categories = categories
      @sections = sections
      @org_param = org_param
      prefill_categories_for_sections
    end

    private

    attr_reader :repository, :categories, :sections

    sig { returns T.nilable(String) }
    attr_reader :org_param

    def render?
      return false unless logged_in?
      repository.present? && categories.present?
    end

    # Private: Indicates whether the current user can create announcements.
    #
    # Returns a Boolean.
    memoize def viewer_can_create_announcements?
      repository.can_create_discussion_announcements?(current_user)
    end

    # Private: Indicates if the current viewer can edit a category.
    #
    # category - The DiscussionCategory to check permissions for.
    #
    # Returns a Boolean.
    def editable_by_viewer?(category)
      return false unless category.present?
      return false unless permission = permissions_for_categories[category.id]
      permission[:editable]
    end

    # Private: Indicates if the current viewer can delete a category.
    #
    # category - The DiscussionCategory to check permissions for.
    #
    # Returns a Boolean.
    def deletable_by_viewer?(category)
      return false unless category.present?
      return false unless permission = permissions_for_categories[category.id]
      permission[:deletable]
    end

    # Private: Information about the current viewer's permissions for each
    #          category.
    #
    # Examples
    #
    #   permissions_for_categories
    #   # => { 123 => { editable: true, deletable: false } }
    #
    # Returns a Hash{Integer => Hash{Symbol => Boolean}}.
    memoize def permissions_for_categories
      promises = categories.map do |category|
        async_permissions_for(category: category)
      end

      permissions = Promise.all(promises).sync

      categories.each_with_object({}) do |category, results|
        results[category.id] = permissions[categories.index(category)]
      end
    end

    # Private: Gets permission data for the current viewer for a category.
    #
    # category - The DiscussionCategory to check permissions for.
    #
    # Examples
    #
    #   async_permissions_for(category: discussion_category)
    #   # => { editable: true, deletable: false }
    #
    # Returns a Promise<Hash{Symbol => Boolean}>.
    def async_permissions_for(category:)
      Promise.all([
        category.async_modifiable_by?(current_user),
        category.async_deletable_by?(current_user),
      ]).then do |editable, deletable|
        { editable: editable, deletable: deletable }
      end
    end

    memoize def can_edit_sections?
      current_user.can_create_discussion_category?(repository)
    end

    def categories_no_section
      categories.reject { |category| category.discussion_section_id.present? }
    end

    def prefill_categories_for_sections
      GitHub::PrefillAssociations.prefill_associations(sections, :discussion_categories, available_records: categories)
    end

    sig { returns String }
    def agnostic_new_section_path
      if org_param.present?
        new_org_discussions_section_path(org: org_param)
      else
        new_section_path(repository.owner_display_login, repository)
      end
    end

    sig { returns String }
    def agnostic_new_category_path
      if org_param.present?
        new_org_discussions_category_path(org: org_param)
      else
        new_category_path(repository.owner, repository)
      end
    end
  end
end
