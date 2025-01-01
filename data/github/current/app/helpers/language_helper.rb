# typed: true
# frozen_string_literal: true

module LanguageHelper

  FALLBACK_COLOR = "#ccc"

  # Get the list of all languages sorted with percentages by letter
  #
  # returns array of languages
  def all_languages
    LanguageName.all_sorted.map(&:language).compact
  end

  def language_color(language)
    # if language exists and has a color use that color
    if language && language.color
      language.color

    # if language exists and doesn't have a color use #ccc
    elsif language
      FALLBACK_COLOR

    # This would be 'Other'
    else
      "#ededed"
    end
  end
end
