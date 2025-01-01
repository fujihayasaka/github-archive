# typed: true
# frozen_string_literal: true

require "wcag_color_contrast"

class ColorCalculator
  attr_reader :color

  # See https://www.w3.org/TR/WCAG20/#visual-audio-contrast7
  IDEAL_CONTRAST = 7 # Level AAA has a 7:1 contrast ratio
  FALLBACK_CONTRAST = 4.5 # Level AA has a 4.5:1 contrast ratio

  def initialize(color)
    @color = color
  end

  # Public: Check if this color will have a readable contrast when used as the background color with
  # the given color as the text.
  #
  # Returns a Boolean.
  def readable_with?(other_color)
    contrast_with(other_color) >= FALLBACK_CONTRAST
  end

  # Public: Perceived brightness (Luma) of the color
  #
  # Return a Number between 0 and 1
  def brightness
    base = Color::RGB.from_html(color)
    # See https://en.wikipedia.org/wiki/Luma_(video)#Rec._601_luma_versus_Rec._709_luma_coefficients
    1 - (0.2989 * base.red + 0.587 * base.green + 0.114 * base.blue) / 255
  end

  # Public: Figures out an appropriate text color given a base color background. Ensures that you
  # don't get black text on a dark red background, etc.
  #
  # Returns a String of a hex color.
  def text_color
    return @text_color if defined?(@text_color)

    candidates = {
      "ffffff" => contrast_with("ffffff"),
      "000000" => contrast_with("000000"),
    }

    # Array like ["feefef", 7.74], or nil
    readable_candidate =
      candidates.detect { |_other_color, contrast| contrast >= IDEAL_CONTRAST } ||
      candidates.detect { |_other_color, contrast| contrast >= FALLBACK_CONTRAST }

    @text_color = if readable_candidate
      # Choose the first variation that has a Level AAA or Level AA contrast
      readable_candidate.first
    else
      # Choose the text color with the best (i.e., biggest) contrast
      candidates.keys.last
    end
  end

  # Public: Returns a floating point ratio of how much contrast is between this color and the given
  # color.
  def contrast_with(other_color)
    WCAGColorContrast.ratio(color.dup, other_color)
  end
end
