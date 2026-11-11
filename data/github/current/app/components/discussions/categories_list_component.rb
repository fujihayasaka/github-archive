# typed: true
# frozen_string_literal: true

module Discussions
  class CategoriesListComponent < ApplicationComponent
    include GitHub::Memoizer

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        current_repository: T.untyped,
        discussions_path: T.untyped,
        categories: T.untyped,
        parsed_discussions_query: T.untyped,
        selected_category_slug: T.untyped,
        can_create_discussion_category: T.untyped,
        can_toggle_discussions_setting: T.untyped,
        can_manage_spotlights: T.untyped,
        categories_heading_tag: T.untyped,
        org_param: T.nilable(String)
      ).void
    end
    def initialize(
      current_repository:,
      discussions_path:,
      categories:,
      parsed_discussions_query:,
      selected_category_slug:,
      can_create_discussion_category:,
      can_toggle_discussions_setting:,
      can_manage_spotlights:,
      categories_heading_tag: :h2,
      org_param: nil
    )
      @current_repository = current_repository
      @discussions_path = discussions_path
      @categories = categories
      @parsed_discussions_query = parsed_discussions_query
      @selected_category_slug = selected_category_slug
      @can_create_discussion_category = can_create_discussion_category
      @can_toggle_discussions_setting = can_toggle_discussions_setting
      @can_manage_spotlights = can_manage_spotlights
      @categories_heading_tag = categories_heading_tag
      @org_param = org_param
    end

    private

    def categories_with_no_section
      current_repository.discussion_categories.where.missing(:discussion_section)
    end

    memoize def sections_to_display
      current_repository
        .discussion_sections
        .includes(:discussion_categories)
        .reject { |section| section.discussion_categories.blank? }
    end

    memoize def section_ids_by_slug
      categories.pluck(:slug, :discussion_section_id).to_h
    end

    def section_expanded?(section)
      @section_expanded ||= {}
      return true if selected_category_slug.blank?
      return @section_expanded[section.id] if @section_expanded.key?(section.id)

      @section_expanded[section.id] = section_ids_by_slug[selected_category_slug] == section.id
    end

    def categories_heading_font_size
      org_param.present? ? 5 : 4
    end

    def show_categories_popover?
      return false if org_param.present? || !logged_in?
      current_repository.show_discussions_categories_popover?(
        current_user,
        can_toggle_discussions_setting: can_toggle_discussions_setting
      )
    end

    def discussion_section_emoji_tag(discussion_section, classes: nil)
      emoji = emoji_for(discussion_section.emoji)
      if emoji
        emoji_tag(emoji, class: classes)
      else
        helpers.primer_octicon("comment-discussion")
      end
    end

    attr_accessor :current_repository,
      :discussions_path,
      :categories,
      :parsed_discussions_query,
      :selected_category_slug,
      :can_create_discussion_category,
      :can_toggle_discussions_setting,
      :can_manage_spotlights,
      :categories_heading_tag

    sig { returns(T.nilable(String)) }
    attr_reader :org_param
  end
end
