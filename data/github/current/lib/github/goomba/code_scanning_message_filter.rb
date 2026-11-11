# typed: true
# frozen_string_literal: true

require_relative "markdown_filter"

module GitHub::Goomba
  # The CodeScanningMessageFilter escapes underscores or stars to avoid markdown turning them into emphasis,
  # but preserves them inside inline code (backticks) which become <code> tags.
  class CodeScanningMessageFilter < MarkdownFilter
    def call(input)
      doc = Nokogiri::HTML5.fragment(input, nil, max_errors: 1)
      doc.xpath(".//text()").each do |node|
        content = node.content

        # Apply escaping, preserving backticks
        result = escape_outside_backticks(content)

        # Apply other escaping
        node.content = result.gsub("\\\\\\\\", "\\")
                             .gsub("\\[", "[")
                             .gsub("\\]", "]")
                             .gsub("{{", "{")
                             .gsub("}}", "}")
      end
      # if the document was malformed give up trying to escape html attributes
      # this prevents NokoGiri 'fixing' the document and potentially causing worse issues.
      return super(input) if doc.errors.present?

      # Process through markdown and restore escaped HTML
      super(CGI.unescapeHTML(doc.to_s))
    end

    private

    # Process the content character by character to handle backticks properly.
    # Escapes underscores and stars outside of backticks, preserves them inside.
    sig { params(content: String).returns(String) }
    def escape_outside_backticks(content)
      result = +""
      in_backtick = T.let(false, T::Boolean)

      content.chars.each_with_index do |char, idx|
        case char
        when "`"
          in_backtick = !in_backtick
          result << char
        when "_", "*"
          # Only escape if outside backticks and followed by non-space
          next_char = content[idx + 1]
          if next_char && next_char != " " && !in_backtick
            result << "\\" << char
          else
            result << char
          end
        else
          result << char
        end
      end

      result
    end
  end
end
