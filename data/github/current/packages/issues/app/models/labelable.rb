# typed: true
# frozen_string_literal: true

# ActiveRecord mixin for classes that behave like labels and require shared validation logic.
# This includes the following models:
#   Label
#   UserLabel
module Labelable

  extend ActiveSupport::Concern

  NAME_MAX_LENGTH = 50
  DESCRIPTION_MAX_LENGTH = 100

  NAME_REGEXP = /\A[^,]*\Z/iu
  COLOR_REGEXP = /\A[0-9a-f]{6}\z/iu # e.g., ff00ff
  COLOR_SHORTHAND_REGEXP = /\A[0-9a-f]{3}\z/iu # e.g., fff

  HELP_WANTED_NAME = "help wanted".freeze
  GOOD_FIRST_ISSUE_NAME = "good first issue".freeze

  DARK_COLORS = %w[b60205 d93f0b fbca04 0e8a16 006b75 1d76db 0052cc
                 5319e7].freeze
  LIGHT_COLORS = %w[e99695 f9d0c4 fef2c0 c2e0c6 bfdadc c5def5 bfd4f2
                  d4c5f9].freeze

  module ClassMethods
    # The initial labels we use while creating a new label owner (either Repository or Organization).
    #
    # Returns an Array of Label representations in Hash form.
    def initial_labels
      [
        {
          name: "bug",
          color: "d73a4a",
          description: "Something isn't working",
        },
        {
          name: "documentation",
          color: "0075ca",
          description: "Improvements or additions to documentation",
        },
        {
          name: "duplicate",
          color: "cfd3d7",
          description: "This issue or pull request already exists",
        },
        {
          name: "enhancement",
          color: "a2eeef",
          description: "New feature or request",
        },
        {
          name: HELP_WANTED_NAME,
          color: "008672",
          description: "Extra attention is needed",
        },
        {
          name: GOOD_FIRST_ISSUE_NAME,
          color: "7057ff",
          description: "Good for newcomers",
        },
        {
          name: "invalid",
          color: "e4e669",
          description: "This doesn't seem right",
        },
        {
          name: "question",
          color: "d876e3",
          description: "Further information is requested",
        },
        {
          name: "wontfix",
          color: "ffffff",
          description: "This will not be worked on",
        },
      ]
    end

    # Figures out a set of default colors to offer for users to choose from.
    # Should create a nice set of colors that look good and are easily
    # distinguishable from one another.
    #
    # num - The Number of default labels.
    #
    # Returns an Array of Labels.
    def defaults
      colors = DARK_COLORS + LIGHT_COLORS

      colors.collect do |color|
        T.unsafe(self).new(name: "default-label-#{color}", color: color)
      end
    end
  end

  # Expands colors of three character length `"000"` into six character hex code `"000000"`.
  def self.expand_color_shorthand(color)
    result = color
    result = [color[0] * 2, color[1] * 2, color[2] * 2].join if color =~ COLOR_SHORTHAND_REGEXP
    result
  end

  # Default color for labels. This is the base background color that will
  # show up.
  #
  # Returns a String of a hex color.
  def color
    T.unsafe(self).read_attribute(:color) || "ededed"
  end

  # Public: Perceived brightness (Luma) of the label's color
  #
  # Return a Number between 0 and 1.
  def brightness
    color_calculator.brightness
  end

  # Public: Calculates an appropriate color for text assuming it's put on a background with this
  # label's color.
  #
  # Returns a String of a hex color.
  def text_color
    color_calculator.text_color
  end

  # Returns the encoded label name for use in a URI.
  #
  # This is specifically meant to be used as a path component vs. a query
  # string param, as their rules for what needs to be escaped are slightly
  # different.
  #
  # Returns a String.
  def to_escaped_param
    UrlHelper.escape_path(T.unsafe(self).name.to_s)
  end

  private

  def color_calculator
    @color_calculator ||= ColorCalculator.new(color)
  end

  # Strips leading or trailing whitespace from name,
  # and replace newlines with spaces.
  def normalize_name
    T.unsafe(self).name = T.unsafe(self).name.strip.gsub(/\n/, " ") if T.unsafe(self).name
  end

  def normalize_description
    T.unsafe(self).description = T.unsafe(self).description.strip.gsub(/\n/, " ") if T.unsafe(self).description
  end

  def set_lowercase_name
    # Load lowercase_name to force utf-8 encoding before setting it.
    # This avoids the attribute being marked as dirty when nothing has changed.
    T.unsafe(self).lowercase_name
    T.unsafe(self).lowercase_name = T.unsafe(self).name.downcase.force_encoding("utf-8") if T.unsafe(self).name
  end

  def name_has_more_than_emoji
    return unless T.unsafe(self).name && T.unsafe(self).name.present?

    name_without_emoji = T.unsafe(self).name.gsub(Label::EMOJI_REGEX, "").strip
    if name_without_emoji.blank?
      T.unsafe(self).errors.add(:name, "must contain more than native emoji")
    end
  end

  # Expands colors of three character length `"000"`
  # into six character hex code `"000000"`.
  def expand_color_shorthand
    T.unsafe(self).color = Labelable.expand_color_shorthand(self.color)
  end

  # Ensures the case-insensitive uniqueness of the name by checking the lowercase_name
  # field. Still sets the error on `:name` since that's the field users can change.
  #
  # Returns nothing.
  def uniqueness_of_name
    return true unless T.unsafe(self).name_changed? && T.unsafe(self).lowercase_name && owner

    other_names = sibling_labels_with_same_name
    other_names = other_names.where("id <> ?", T.unsafe(self).id) if T.unsafe(self).persisted?

    T.unsafe(self).errors.add(:name, "has already been taken") if other_names.exists?
  end

  def sibling_labels_with_same_name
    Kernel.raise NotImplementedError, "This method must be implemented in a class that includes this module."
  end

  def owner
    Kernel.raise NotImplementedError, "This method must be implemented in a class that includes this module."
  end
end
