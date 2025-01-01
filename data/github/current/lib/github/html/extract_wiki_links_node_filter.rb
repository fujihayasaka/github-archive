# typed: true
# frozen_string_literal: true

module GitHub::HTML
  class ExtractWikiLinksNodeFilter < ::HTML::Pipeline::Filter
    def call
      result[:wiki_links] = {}
      # Nasty selector due to nokogiri bug:
      # https://github.com/sparklemotion/nokogiri/issues/572
      doc.xpath("./text()|.//text()").each do |node|
        content = node.to_html
        content = ExtractWikiLinksFilter.operate_on_text(content, result)
        node.replace(content)
      end
      doc
    end
  end
end
