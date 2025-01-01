# typed: false
# frozen_string_literal: true

module TopicsHelper
  # Public: Given a language name and the current selected language, this will return
  # either a `span` or an `a` HTML tag for use in a `select-menu-list`.
  #
  # raw_language_name - String language name, e.g., "Ruby", or nil
  # current_language - String language name or nil
  #
  # Returns HTML.
  def search_language_menu_item(raw_language_name, current_language)
    language_name = raw_language_name.try(:downcase)

    item_params = {
      class: "select-menu-item",
      role: "menuitemradio",
      href: url_with(l: language_name, after: nil),
      "aria-checked": language_name == current_language.try(:downcase),
    }
    content_tag(:a, item_params) { yield }
  end

  def topic_feeds_enabled?
    GitHub.conduit_feed_enabled? && user_feature_enabled?(:topic_feeds)
  end

  def topic_followers_formatted(topic)
    unit_label = "follower".pluralize(topic.stargazer_count)
    if topic.stargazer_count == 0
      return "No #{unit_label}"
    end

    "#{social_count(topic.stargazer_count)} #{unit_label}"
  end
end
