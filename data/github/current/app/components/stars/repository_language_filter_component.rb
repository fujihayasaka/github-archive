# typed: true
# frozen_string_literal: true

module Stars
  class RepositoryLanguageFilterComponent < ApplicationComponent
    # user - the User whose starred repositories should be filtered
    # selected_language - String language name for which language is currently selected in the filter, if any;
    #                     e.g., "ruby"
    # user_path_params - optional Hash of parameters to be used to construct the path to the user profile Stars tab
    # phrase - String or nil representing the current search phrase, if one is present
    def initialize(user:, selected_language: nil, user_path_params: {}, phrase: nil, **system_arguments)
      @user = user
      @selected_language = selected_language.presence&.downcase
      @user_path_params = user_path_params
      @phrase = phrase
      @system_arguments = system_arguments
    end

    private

    attr_reader :user, :selected_language, :user_path_params, :phrase

    def render?
      user.present? && languages.any?
    end

    # Private: Returns alphabetized list of languages for the user's starred
    # repositories.
    memoize def languages
      starred_repo_count_by_language_name.keys.sort
    end

    def starred_repo_count_by_language_name
      user.cached_starred_repository_count_by_language_name(viewer: current_user)
    end

    def button_text
      if selected_language_name.present?
        "Language: #{selected_language_name}"
      else
        "Language"
      end
    end

    memoize def selected_language_name
      if selected_language.present?
        languages.detect { |language| language.downcase == selected_language }
      end
    end

    def user_path_params_for(language)
      @user_path_params.merge(tab: "stars", q: phrase, language: language.downcase).compact_blank
    end
  end
end
