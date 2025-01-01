# typed: true
# frozen_string_literal: true

module Stars
  class RepositoryTypeFilterComponent < ApplicationComponent
    include UserRepositoriesHelper

    # user - the User whose starred repositories should be filtered
    # selected_type - String indicating the repo type filter that's active; choose from "public", "private", "source",
    #                 "mirror", "fork", "sponsorable"; see Enums::StarredRepositoryType; nil means no type filter is
    #                 applied
    # user_path_params - optional Hash of parameters to be used to construct the path to the user profile Stars tab
    # phrase - String or nil representing the current search phrase, if one is present
    def initialize(user:, selected_type: nil, user_path_params: {}, phrase: nil, **system_arguments)
      @user = user
      @selected_type = selected_type
      @user_path_params = user_path_params
      @phrase = phrase
      @system_arguments = system_arguments
    end

    private

    attr_reader :user, :selected_type, :user_path_params, :phrase

    def render?
      user.present?
    end

    memoize def type_filters
      user_repositories_valid_type_filters(
        include_private: logged_in? && user == current_user,
        include_public: user.is_enterprise_managed?,
        include_archived: false, # can't have a starred archived repo
      )
    end

    def button_text
      if selected_type.present?
        "Type: #{selected_type_filter(type: selected_type, types: type_filters)}"
      else
        "Type: All"
      end
    end

    def user_path_params_for(type_value)
      @user_path_params.merge(tab: "stars", q: phrase, type: type_value).compact_blank
    end
  end
end
