# typed: true
# frozen_string_literal: true

module Stars
  class RepositoryFilterComponent < ApplicationComponent
    # user - the User whose starred repositories should be filtered
    # phrase - the current search phrase, if any; String or nil
    # selected_language - the current language filter, if any; String (like "javascript") or nil
    # selected_field - the field to sort starred repositories by; see Stars::RepositorySortMenuComponent::SORT_OPTIONS
    # selected_direction - the direction to sort starred repositories in; choose from "asc" or "desc"
    # selected_type - String indicating the repo type filter that's active
    # has_starred_topics - Boolean indicating whether the user has starred any topics
    def initialize(user:, starred_repository_count:, phrase: nil, selected_language: nil, selected_field: nil, selected_direction: nil, selected_type: nil, has_starred_topics: false)
      @user = user
      @phrase = phrase
      @selected_language = selected_language
      @selected_field = selected_field
      @selected_direction = selected_direction
      @selected_type = selected_type
      @has_starred_topics = has_starred_topics
      @starred_repository_count = starred_repository_count
    end

    private

    attr_reader :user, :starred_repository_count, :phrase, :selected_language, :selected_field, :selected_direction, :selected_type

    def render?
      user.present? && !starred_repositories_over_limit?
    end

    def starred_repositories_over_limit?
      starred_repository_count > Star::STARRED_REPOSITORY_LIMIT
    end

    def has_starred_topics?
      @has_starred_topics
    end

    memoize def search_placeholder
      if has_starred_topics?
        "Search starred repositories"
      else
        "Search stars"
      end
    end

    memoize def user_path_params
      {
        language: selected_language,
        sort: selected_field,
        direction: selected_direction,
        type: selected_type,
      }.reject { |_k, v| v.blank? }
    end
  end
end
