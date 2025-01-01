# typed: true
# frozen_string_literal: true

class Platform::Models::TextMatch
  attr_reader :fragment, :property, :highlights

  # A specific fragment match in a TextMatch
  class Highlight
    attr_reader :text, :begin_indice, :end_indice

    def initialize(text:, begin_indice:, end_indice:)
      @text, @begin_indice, @end_indice = text, begin_indice, end_indice
    end

    def platform_type_name
      "TextMatchHighlight"
    end
  end

  def initialize(fragment:, property:, indices:)
    @fragment, @property, @indices = fragment, property, indices
    @highlights = build_highlights
  end

  private

  def build_highlights
    match_indices = @indices.each_slice(2).to_a

    match_indices.map do |match_indice|
      text = fragment[match_indice.first..match_indice.second - 1]
      Highlight.new(text: text, begin_indice: match_indice.first, end_indice: match_indice.second)
    end
  end
end
