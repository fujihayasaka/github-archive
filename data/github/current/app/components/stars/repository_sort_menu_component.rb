# typed: true
# frozen_string_literal: true

module Stars
  class RepositorySortMenuComponent < ApplicationComponent
    RECENTLY_STARRED_TITLE = "Recently starred"
    DEFAULT_DIRECTION = "desc"

    SORT_OPTIONS = {
      RECENTLY_STARRED_TITLE => %w[created desc],
      "Recently active"      => %w[updated desc],
      "Most stars"           => %w[stars desc],
    }.freeze

    # user - the User whose starred repositories will be sorted
    # selected_direction - which String direction to sort the repositories in; choose from "asc" or "desc"
    # selected_field - which String field to sort repositories by; see SORT_OPTIONS for available fields
    # user_path_params - optional Hash of parameters to be used to construct the path to the user profile Stars tab
    # phrase - the current search phrase as a String, if any, or nil
    def initialize(
      user:,
      selected_direction: nil,
      selected_field: nil,
      user_path_params: {},
      phrase: nil,
      **system_arguments
    )
      @user = user
      @user_path_params = user_path_params
      @phrase = phrase
      @system_arguments = system_arguments

      @selected_direction = value_or(%w[desc asc], selected_direction&.downcase, DEFAULT_DIRECTION)
      @selected_field = value_or(supported_sort_option_fields, selected_field&.downcase, default_field)
    end

    private

    attr_reader :selected_direction, :selected_field, :user, :user_path_params, :phrase

    def render?
      user.present?
    end

    def supports_recently_starred_sort?
      phrase.blank? && user_path_params[:language].blank?
    end

    def default_field
      if supports_recently_starred_sort?
        "created"
      else
        "stars"
      end
    end

    def supported_sort_option_fields
      SORT_OPTIONS.filter_map do |title, (field, _direction)|
        field if title != RECENTLY_STARRED_TITLE || supports_recently_starred_sort?
      end
    end

    # Like fetch_or_fallback, but doesn't raise in dev/test.
    def value_or(options, value, default)
      if value.in?(options)
        value
      else
        default
      end
    end

    def each_sort_option
      SORT_OPTIONS.each do |title, (field, direction)|
        next if title == RECENTLY_STARRED_TITLE && !supports_recently_starred_sort?
        yield title, field, direction
      end
    end

    def button_text
      sort_value = [selected_field, selected_direction]
      sort_description = SORT_OPTIONS.key(sort_value)
      if sort_description
        "Sort by: #{sort_description}"
      else
        "Sort"
      end
    end

    def user_path_params_for(field, direction)
      @user_path_params.merge({
        tab: "stars",
        q: phrase,
        sort: field,
        direction: direction,
      }.reject { |_k, v| v.blank? })
    end
  end
end
