# typed: true
# frozen_string_literal: true

module Search

  # The whole point of this module is to highlight the text_matches returned by
  # the dotcom_api
  #
  # When you request for search results, this module
  # will attach inline tags marking the beginning and the end of the highlighted
  # text.
  #
  class DotcomHighlights
    def self.helpers
      @helpers ||= ViewModel::Helpers.new(self)
    end

    def self.highlights(text_matches)
      return nil unless text_matches.present?

      highlights = Hash.new
      text_matches.each do |text_match|
        key = text_match["property"]
        output = ActiveSupport::SafeBuffer.new("")
        fragment = text_match["fragment"].dup
        inserted = 0
        text_match["matches"].map do |matches|
          preamble = fragment[inserted...matches["indices"].first]
          highlight = fragment[matches["indices"].first...matches["indices"].last]
          output << preamble
          output << helpers.content_tag(:em, highlight) # rubocop:disable Rails/ViewModelHTML
          inserted += preamble.length + highlight.length
        end
        postamble = fragment[inserted...fragment.length]
        output << postamble
        highlights[key.to_s] = [output]
      end
      highlights
    end
  end
end
