# typed: true
# frozen_string_literal: true

require "digest/sha2"

module GitHub::HTML
  # Extract all code blocks into the codemap and replace with placeholders.
  class ExtractWikiCodeBlocksFilter < ::HTML::Pipeline::TextFilter
    CodeBlockRegex = /^([ \t]*)``` ?([^\r\n]+)?\r?\n(.+?)\r?\n\1```\r?$/m

    def call
      return @text if context[:page].format == :markdown

      result[:code_blocks] = {}

      @text.gsub!(CodeBlockRegex) do |_match|
        id = Digest::SHA256.hexdigest("#{$2}.#{$3}")
        result[:code_blocks][id] = { lang: $2, code: $3, indent: $1 }
        "#{$1}#{id}" # print the ID with the proper indentation
      end

      @text
    end
  end
end
