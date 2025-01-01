# typed: true
# frozen_string_literal: true

module Localization
  module AzureTranslations
    # This splits a html fragment into chunks of max_length without breaking markup
    class HtmlSplitter
      SplitError = Class.new(RuntimeError)

      def initialize(max_length: 50_000)
        @length = max_length

        # This is a list of selectors for elements that can be split into chunks.
        # If paragraphs turn out not to be enough, we can add selectors for other
        # elements that can pottentially hold translatable text.
        @placeholder_selectors = ["p"]
      end

      # @return <SplitResult>
      def split(html)
        if acceptable_length?(html)
          return SplitResult.new(html, [])
        end

        doc = parse_html(html)
        extracted_elements = []

        @placeholder_selectors.each do |selector|
          doc = placeholder(doc, selector, extracted_elements)
          result = SplitResult.new(doc.to_html, create_fragments(extracted_elements))

          if valid?(result)
            return result
          end
        end

        raise SplitError, "Content is too long. Cannot split content into chunks of #{@length} chars."
      end

      private

      def acceptable_length?(string, offset: 0)
        (string.length - 0) <= @length
      end

      def parse_html(html)
        HTML::Pipeline.parse(html)
      end

      def placeholder(doc, selector, extracted)
        doc.search(selector).each do |node|
          id = next_id
          node.set_attribute("data-tph", id)
          extracted.push(node.to_html)
          node.replace("<span data-tph=\"#{id}\"></span>")
        end

        doc
      end

      def create_fragments(elements)
        fragments = [""]
        offset = "<div></div>".length

        elements.each do |element|
          html = fragments.last
          candidate = "#{html}#{element}"

          unless acceptable_length?(candidate, offset: offset)
            next fragments.push(element)
          end

          fragments[fragments.length - 1] = candidate
        end

        fragments.map { |item| "<div>#{item}</div>" }
      end

      # TPH stands for Translation Placeholder
      def next_id
        "s#{SecureRandom.uuid}"
      end

      def valid?(result)
        result.lengths.max <= @length
      end
    end
  end
end
