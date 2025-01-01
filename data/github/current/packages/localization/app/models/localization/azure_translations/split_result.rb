# typed: true
# frozen_string_literal: true

module Localization
  module AzureTranslations
    # this class is respnonsible for holding the pieces of a long html string
    # and joining them together upon request
    class SplitResult
      def initialize(frame, fragments)
        @frame = frame
        @fragments = fragments.compact_blank
      end

      def join
        frame = parse_html(@frame)
        @fragments.each do |fragment|
          move_fragment(frame, parse_html(fragment))
        end
        frame.to_html
      end

      def pieces
        [@frame, @fragments].flatten
      end

      def length
        @length ||= pieces.length
      end

      def lengths
        @lengths ||= pieces.map(&:length)
      end

      def translate(from:, to:, translation_client:)
        translations = pieces.map do |text|
          response = translation_client.translate(text, from: from, to: to)
          response.first[:translations].map { |t| t[:text] }
        end.flatten

        SplitResult.new(translations.shift, translations)
      end

      private

      def parse_html(html)
        HTML::Pipeline.parse(html)
      end

      def move_fragment(frame, fragment)
        fragment.search("[data-tph]").each do |node|
          ph = node.attribute("data-tph")
          node.remove_attribute("data-tph")
          replace_placeholder(frame, ph, node)
        end
      end

      def replace_placeholder(frame, ph, node)
        found = frame.at_css("[data-tph='#{ph}']")

        if found
          found.replace(node)
        end
      end
    end
  end
end
