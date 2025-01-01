# typed: true
# frozen_string_literal: true

module Discussions
  class SearchAndCreateComponent < ApplicationComponent
    extend T::Sig
    include EnterpriseManagedUsersHelper
    include SearchHelper
    include GitHub::BrowserStatsHelper

    sig do
      params(
        current_repository: T.untyped,
        query: T.untyped,
        can_create_discussion: T.untyped,
        can_toggle_discussions_setting: T.untyped,
        selected_category_slug: T.untyped,
        include_answer_filters: T.untyped,
        parsed_discussions_query: T.untyped,
        current_user_can_push: T.untyped,
        org_level: T.untyped,
        org: T.nilable(Organization)
      ).void
    end
    def initialize(
      current_repository:,
      query:,
      can_create_discussion:,
      can_toggle_discussions_setting:,
      selected_category_slug:,
      include_answer_filters:,
      parsed_discussions_query:,
      current_user_can_push:,
      org_level:,
      org: nil
    )
      @current_repository = current_repository
      @query = query
      @can_create_discussion = can_create_discussion
      @can_toggle_discussions_setting = can_toggle_discussions_setting
      @selected_category_slug = selected_category_slug
      @include_answer_filters = include_answer_filters
      @parsed_discussions_query = parsed_discussions_query
      @current_user_can_push = current_user_can_push
      @org_level = org_level
      @org = org
    end

    private

    attr_reader :current_repository, :query, :can_create_discussion, :can_toggle_discussions_setting,
      :selected_category_slug, :include_answer_filters, :parsed_discussions_query, :org_level

    sig { returns T.nilable(Organization) }
    attr_reader :org

    alias :include_answer_filters? :include_answer_filters

    def new_discussion_hydro_attrs
      helpers.safe_discussions_list_click_attrs(nil, target: :NEW_DISCUSSION_LINK)
    end

    def could_create_discussion_if_verified?
      logged_in? && current_user.no_verified_emails? && helpers.can_interact_with_repo?
    end

    def current_user_can_push?
      @current_user_can_push
    end

    def create_new_discussion_path
      if selected_category_slug.blank?
        agnostic_choose_category_discussion_path(current_repository, org: org)
      else
        agnostic_new_discussion_path(current_repository, org_param: org_param, category: selected_category_slug)
      end
    end

    sig { returns T.nilable(String) }
    def org_param
      @org&.to_param if @org_level
    end

    def search_path
      query = []

      # If a category is selected, we should search with that URL.
      # `Discussions::ListControlFlow` will redirect if needed.
      if selected_category_slug.present?
        query = [[:category, selected_category_slug]]
      end

      helpers.discussions_search_path(discussions_query: query, org_param: org_param)
    end

    # Private: For a given sort filter value, get the name for hydro tracking
    #
    # sort_filter - Optional String sort filter that would show in the search box, e.g. "created-desc".
    #
    # Returns a String that's a lowercased version of the Hydro sort enum, e.g. "newest"
    def discussion_sort_option_tracking_name(sort_filter = discussions_current_sort)
      return nil unless sort_filter

      if sort_filter == "top"
        "top"
      elsif sort_filter == "latest"
        "newest"
      end
    end

    def discussions_current_sort
      Discussion::SearchTerm.values(:sort, parsed_discussions_query: parsed_discussions_query).first || "latest"
    end

    def discussion_category_suggestions
      categories = (current_repository&.available_discussion_categories || []).map do |category|
        { value: "#{category.name.to_json}" }
      end
      categories.to_json
    end
  end
end
