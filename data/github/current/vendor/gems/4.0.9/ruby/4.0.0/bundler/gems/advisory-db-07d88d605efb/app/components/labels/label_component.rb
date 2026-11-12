# frozen_string_literal: true

module Labels
  class LabelComponent < ApplicationComponent
    # See https://www.w3.org/TR/WCAG20/#visual-audio-contrast7
    IDEAL_CONTRAST = 7 # Level AAA has a 7:1 contrast ratio
    FALLBACK_CONTRAST = 4.5 # Level AA has a 4.5:1 contrast ratio

    attr_reader :name, :background_color, :link

    def initialize(name:, color:, link: nil)
      @name = name
      @background_color = color
      @link = link
    end

    def text_color
      return @text_color if defined?(@text_color)

      candidates = {
        "ffffff" => WCAGColorContrast.ratio(background_color.dup, "ffffff"),
        "000000" => WCAGColorContrast.ratio(background_color.dup, "000000"),
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

    def label
      render Primer::Beta::Label.new(
        title: name,
        style: "background-color: ##{background_color}; border-color: ##{background_color}; color: ##{text_color}",
        test_selector: "label-content",
      ) do
        name
      end
    end
  end
end
