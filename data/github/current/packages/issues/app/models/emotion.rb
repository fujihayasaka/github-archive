# typed: true
# frozen_string_literal: true

require "emoji"

class Emotion
  # Internal: Index mapping Emotion content String to Emotion value object.
  CONTENT_INDEX = {}

  # Internal: Index mapping Emotion label String to Emotion value object.
  LABEL_INDEX = {}

  # Internal: Index mapping Emotion platform_enum String to Emotion value object.
  PLATFORM_ENUM_INDEX = {}

  # Public: Get all Emotion value objects.
  #
  # Returns an Array of Emotions.
  def self.all
    CONTENT_INDEX.values
  end

  # Public: Lookup Emotion by content String.
  #
  # content - String
  #
  # Returns Emotion or nil.
  def self.find(content)
    CONTENT_INDEX[content.to_s]
  end

  # Public: Lookup Emotion index by content String.
  #
  # content - String
  #
  # Returns Integer or nil.
  def self.find_index(content)
    all.find_index { |emotion| emotion.content == content }
  end

  # Public: Lookup Emotion by ReactionContentEnum String.
  #
  # content - String
  #
  # Returns Emotion or nil.
  def self.find_by_platform_enum(content)  # rubocop:disable GitHub/FindByDef
    PLATFORM_ENUM_INDEX[content.to_s]
  end

  # Public: Lookup Emotion by label String.
  #
  # label - String
  #
  # Returns Emotion or nil.
  def self.find_by_label(label)  # rubocop:disable GitHub/FindByDef
    LABEL_INDEX[label.to_s.downcase]
  end

  # Internal: Create new Emotion value object.
  #
  # Returns Emotion.
  def self.create(**kargs)
    emotion = T.unsafe(self).new(**kargs)
    CONTENT_INDEX[emotion.content] = emotion
    LABEL_INDEX[emotion.label] = emotion
    PLATFORM_ENUM_INDEX[emotion.platform_enum] = emotion
    emotion
  end

  # Public: Get the database enum value for Emotion.
  #
  # Returns a String.
  attr_reader :content

  # Public: Get content enum for ReactionContentEnum value.
  #
  # Returns a String.
  attr_reader :platform_enum

  # Public: Get a publicly-displayable description.
  #
  # Returns a String.
  attr_reader :label

  attr_reader :pronounceable_label

  # Public: Get the Emoji that this reaction's content represents.
  #
  # Returns an Emoji.
  attr_reader :emoji_character

  def initialize(content:, label: nil, pronounceable_label: nil, emoji_character: nil)
    @content = content
    @label = label || @content
    @pronounceable_label = pronounceable_label || @label
    @emoji_character = emoji_character || Emoji.find_by_alias(@content)
    @platform_enum = @pronounceable_label.gsub(" ", "_").upcase

    freeze
  end
end

Emotion.create(content: "+1", pronounceable_label: "thumbs up")
Emotion.create(content: "-1", pronounceable_label: "thumbs down")
Emotion.create(content: "smile", label: "laugh")
Emotion.create(content: "tada", label: "hooray")
Emotion.create(content: "thinking_face", label: "confused", emoji_character: Emoji.find_by_alias("confused"))
Emotion.create(content: "heart")
Emotion.create(content: "rocket")
Emotion.create(content: "eyes")
