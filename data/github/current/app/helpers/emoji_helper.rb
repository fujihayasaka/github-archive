# typed: true
# frozen_string_literal: true

module EmojiHelper
  extend T::Helpers
  requires_ancestor { ActionView::Helpers }

  # Public: Get the emoji represented by the given string.
  #
  # emoji_name - colon-style or Unicode emoji as a String
  #
  # Returns nil or an Emoji::Character.
  def emoji_for(emoji_name)
    return unless emoji_name

    if emoji_name.start_with?(":") && emoji_name.end_with?(":")
      name_without_colons = emoji_name[1...-1]
      Emoji.find_by_alias(name_without_colons)
    else
      # Handle a value like "smile" or the raw emoji character
      Emoji.find_by_alias(emoji_name) || Emoji.find_by_unicode(emoji_name)
    end
  end

  # Public: Given an Emoji, returns the attributes for the g-emoji or img tag. Supports both native
  # emoji and custom GitHub emoji.
  def emoji_attributes(emoji, attributes = {})
    img_path = "icons/emoji/#{emoji.image_filename}"

    if emoji.raw
      default_attributes = { alias: emoji.name }
      default_attributes[:"fallback-src"] = image_path(img_path) if attributes[:tone].nil? || attributes[:tone] == 0

      { tag: "g-emoji", img_path: img_path, attributes: default_attributes.merge(attributes) }
    else
      default_attributes = {
        size: "20x20",
        align: "absmiddle",
        alt: ":#{emoji.name}:",
        class: "emoji",
      }

      { tag: "img", img_path: img_path, attributes: default_attributes.merge(attributes) }
    end
  end

  # Public: Given an Emoji, renders that emoji as an image. Supports both native
  # emoji and custom GitHub emoji.
  def emoji_tag(emoji, attributes = {})
    attributes = emoji_attributes(emoji, attributes)
    case attributes[:tag]
    when "g-emoji"
      content_tag("g-emoji", emoji.raw, attributes[:attributes])
    when "img"
      image_tag(attributes[:img_path], attributes[:attributes])
    end
  end

  # Public: Given an Emoji, returns the aria-label based on the emoji name. Supports both native
  # emoji and custom GitHub emoji.
  def emoji_aria_label(emoji)
    case emoji.name
    when "+1"
      "thumbs up"
    when "-1"
      "thumbs down"
    else
      emoji.name
    end
  end
end
