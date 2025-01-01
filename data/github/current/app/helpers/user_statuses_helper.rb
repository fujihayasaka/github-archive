# typed: false
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module UserStatusesHelper
  include ActionView::Helpers::DateHelper
  include StaticAssetHelper

  FALLBACK_EMOJI_CATEGORY = "Other"

  def self.expiration_intervals
    [
      { words: "in 30 minutes", time: 30.minutes.from_now.iso8601 },
      { words: "in 1 hour", time: 1.hour.from_now.iso8601 },
      { words: "in 4 hours", time: 4.hours.from_now.iso8601 },
      { words: "after today", time: Time.current.end_of_day.iso8601 },
      { words: "after this week", time: Time.current.end_of_week.iso8601 },
      { words: "after a month", time: Time.current.next_month.iso8601 },
    ]
  end

  def render_user_status_emoji_or_placeholder(emoji_html, message)
    return emoji_html if emoji_html

    if message.present?
      emoji = Emoji.find_by_alias("thought_balloon")
      render_emoji(emoji)
    else
      octicon(:smiley)
    end
  end

  # Public: Determine if the given text value represents the given emoji.
  #
  # value - String
  # emoji - Emoji::Character
  #
  # Returns a Boolean.
  def selected_emoji?(value, emoji)
    return false if value.blank? && !emoji.nil?
    value == ":#{emoji.name}:" || value == emoji.raw
  end

  # Public: Returns a hash of predefined user status emoji + message combinations.
  def predefined_user_statuses_with_emoji
    list = UserStatus::PREDEFINED_STATUSES.map do |emoji_name, message|
      emoji = Emoji.find_by_alias(emoji_name)
      [emoji, message]
    end
    list.to_h
  end

  def render_emoji(emoji, attributes = {})
    if emoji.raw
      emoji_tag(emoji, attributes)
    else
      emoji_image_tag(emoji, attributes)
    end
  end

  def emoji_image_tag(emoji, attributes = {})
    default_attributes = {
      class: "emoji",
      size: "20x20",
      align: "absmiddle",
      alt: ":#{emoji.name}:",
    }
    image_tag(image_path("icons/emoji/#{emoji.image_filename}"),
              default_attributes.merge(attributes))
  end

  def default_emoji_category
    emoji_categories.first
  end

  # Public: Determine if the given category of emoji should be the one that's selected.
  #
  # emoji - the currently selected emoji, if any; Emoji::Character or nil
  # category - emoji category name as a String
  #
  # Returns a Boolean.
  def selected_emoji_category?(emoji, category)
    if emoji
      if emoji.category
        category == emoji.category
      else
        category == FALLBACK_EMOJI_CATEGORY
      end
    else
      category == default_emoji_category
    end
  end

  # Public: Get known aliases for a given emoji.
  #
  # emoji - Emoji::Character
  #
  # Returns a String of space-separated emoji aliases which may themselves contain spaces.
  def emoji_aliases(emoji)
    (emoji.aliases + emoji.tags).join(" ")
  end

  # Public: Get a value for the given emoji name to be used when filtering emoji.
  #
  # emoji_name - String
  #
  # Returns a String where underscores have been replaced with spaces.
  def emoji_filter_value(emoji_name)
    emoji_name.gsub(/_/, " ")
  end

  # Public: Returns a list of categories to organize emoji in the emoji picker.
  #
  # Returns an Array of Strings.
  def emoji_categories
    emoji_category_index.keys
  end

  # Public: Get a list of emoji characters we support for user statuses.
  #
  # Returns an Array of Emoji::Characters.
  def user_status_emoji
    @user_status_emoji ||= GitHub::Emoji.each.
      reject { |emoji| UserStatus.blocked_emoji?(":#{emoji.name}:") }
  end

  # Public: Get a hash of emoji categories and the emoji in each.
  #
  # Returns a Hash of String => Array of Emoji::Characters.
  def emoji_category_index
    @emoji_category_index ||= user_status_emoji.
      group_by { |emoji| emoji.category || FALLBACK_EMOJI_CATEGORY }
  end

  # Public: Return a g-emoji or img HTML tag for the emoji with the given alias.
  #
  # emoji_alias - a String like "grinning"
  #
  # Returns HTML.
  def emoji_icon_for(emoji_alias)
    emoji = Emoji.find_by_alias(emoji_alias)
    render_emoji(emoji, class: "emoji emoji-icon")
  end

  # Public: Get an icon to represent the given emoji category.
  #
  # category - one of the emoji categories from #emoji_categories; a String
  #
  # Returns HTML.
  def emoji_category_icon_for(category)
    case category
    when "Smileys & Emotion" then emoji_icon_for("grinning")
    when "People & Body" then emoji_icon_for("wave")
    when "Animals & Nature" then emoji_icon_for("turtle")
    when "Food & Drink" then emoji_icon_for("orange")
    when "Activities" then emoji_icon_for("baseball")
    when "Travel & Places" then emoji_icon_for("blue_car")
    when "Objects" then emoji_icon_for("tv")
    when "Symbols" then emoji_icon_for("purple_heart")
    when "Flags" then emoji_icon_for("triangular_flag_on_post")
    when FALLBACK_EMOJI_CATEGORY then emoji_icon_for("octocat")
    else
      if Rails.env.test? || Rails.env.development?
        raise "Unexpected emoji category #{category.inspect}"
      end
      category
    end
  end

  def current_user_status_expires_at(expires_at)
    time_diff = (expires_at - Time.current)
    duration =  time_diff / 1.hour
    words = distance_of_time_in_words(duration.hours).gsub(/about/, "in")

    if words =~ /\A\d/
      "in #{words}"
    else
      words
    end
  end
end
