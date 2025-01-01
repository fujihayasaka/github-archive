# typed: true
# frozen_string_literal: true

require_relative "markdown_filter"

module GitHub::Goomba
  # The CodeScanningMessageFilter escape any underscores or stars to avoid markdown turning them into html
  class CodeScanningMessageFilter < MarkdownFilter
    def call(input)
      doc = Nokogiri::HTML5.fragment(input, nil, max_errors: 1)
      doc.xpath(".//text()").each do |node|
        node.content = node.content.gsub(/([_*])(?=\S)/, "\\\\\\1")
                                   .gsub("\\\\\\\\", "\\")
                                   .gsub("\\[", "[")
                                   .gsub("\\]", "]")
                                   .gsub("{{", "{")
                                   .gsub("}}", "}")
      end
      # if the document was malformed give up trying to escape html attributes
      # this prevents NokoGiri 'fixing' the document and potentially causing worse issues.
      return super(input) if doc.errors.present?
      # restore any escaped html entities as they will be escaped later in the pipeline
      super(CGI.unescapeHTML(doc.to_s))
    end
  end
end
