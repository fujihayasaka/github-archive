# typed: true
# frozen_string_literal: true

module Discussions
  class DiscussionsRepoSidebarComponent < ApplicationComponent
    include RepositoryContributorHelper

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        can_create_discussion_category: T.untyped,
        categories: T.untyped,
        can_toggle_discussions_setting: T.untyped,
        can_manage_spotlights: T.untyped,
        selected_category_slug: T.untyped,
        parsed_discussions_query: T.untyped,
        current_repository: T.untyped,
        org_param: T.nilable(String)
      ).void
    end
    def initialize(can_create_discussion_category:,
      categories:,
      can_toggle_discussions_setting:,
      can_manage_spotlights:,
      selected_category_slug:,
      parsed_discussions_query:,
      current_repository:,
      org_param: nil
    )
      @can_create_discussion_category = can_create_discussion_category
      @categories = categories
      @can_toggle_discussions_setting = can_toggle_discussions_setting
      @can_manage_spotlights = can_manage_spotlights
      @selected_category_slug = selected_category_slug
      @parsed_discussions_query = parsed_discussions_query
      @current_repository = current_repository
      @org_param = org_param
    end

    private

    attr_reader :can_create_discussion_category,
      :categories,
      :can_toggle_discussions_setting,
      :can_manage_spotlights,
      :selected_category_slug,
      :parsed_discussions_query,
      :current_repository

    sig { returns T.nilable(String) }
    attr_reader :org_param

    def show_parent_heading?
      categories.any?(&:supports_mark_as_answer?) || show_community_links?
    end

    def categories_heading_tag
      show_parent_heading? ? :h3 : :h2
    end

    def parent_heading
      heading = ["Categories"]
      heading.append("most helpful") if categories.any?(&:supports_mark_as_answer?)
      heading.append("community links") if show_community_links?
      heading.to_sentence
    end

    memoize def show_community_links?
      (code_of_conduct_file.present? ||
        !GitHub.enterprise?) ||
        current_repository.homepage.present? ||
        current_repository.can_view_community_insights?(current_user)
    end

    def show_discussions_categories_popover?
      logged_in? &&
        current_repository.show_discussions_categories_popover?(
          current_user,
          can_toggle_discussions_setting: can_toggle_discussions_setting
        )
    end
  end
end
