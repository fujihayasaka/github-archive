# typed: false
# frozen_string_literal: true

module Trending::FeedHelper
  COUNTRY_NAME_CHARACTER_LIMIT = 25
  DATE_OPTIONS = {
    daily: { text: "today", period: 1.day.ago },
    weekly: { text: "this week", period: 7.days.ago },
    monthly: { text: "this month", period: 1.month.ago },
  }
  LANGUAGE_NAME_CHARACTER_LIMIT = 25
  UNKNOWN_LANGUAGE_NAME = "unknown"
  UNKNOWN_SPOKEN_LANGUAGE_CODE = "unknown"

  def programming_languages(user_languages = [])
    other_languages = all_linguist_languages - user_languages

    [
      user_languages,
      UnknownProgrammingLanguage.new,
      other_languages,
    ].flatten
  end

  def all_linguist_languages
    @_all_linguist_languages ||= all_languages
  end

  def display_language_name_for(language_name)
    return if language_name.nil?
    return UNKNOWN_LANGUAGE_NAME.humanize if language_name == UNKNOWN_LANGUAGE_NAME

    language = safe_find_linguist_language(language_name)
    language&.name
  end

  def safe_find_linguist_language(language_name)
    deparameterized_language_name = language_name.split("-").join(" ")

    Linguist::Language.find_by_name(deparameterized_language_name) ||
      Linguist::Language.find_by_name(language_name) ||
      Linguist::Language.find_by_alias(language_name)
  end

  def since_text(since)
    DATE_OPTIONS.fetch(since.to_s.to_sym, DATE_OPTIONS[:daily])[:text]
  end

  def spoken_language_name_for(spoken_language_code)
    if spoken_language_code == UNKNOWN_SPOKEN_LANGUAGE_CODE
      "Unknown"
    else
      Trending::SpokenLanguageFinder
        .from_code(spoken_language_code)
        .name&.truncate(LANGUAGE_NAME_CHARACTER_LIMIT)
    end
  end

  def programming_language_link_class_names_for(language, language_list_entry)
    [
      "select-menu-item",
      language == language_list_entry.default_alias ? "selected" : nil,
    ].compact.join(" ")
  end

  class UnknownProgrammingLanguage
    def default_alias
      "unknown"
    end

    def name
      "Unknown languages"
    end
  end
end
