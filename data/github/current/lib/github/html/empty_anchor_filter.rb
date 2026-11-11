# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # Strip empty anchors, e.g.
  # <p><a>GitHUb is awesome</a></p> -> <p>GitHUb is awesome</p>
  class EmptyAnchorFilter < Filter
    def call
      doc.xpath(".//a[not(@href) and not(@id) and not(@name)]").each do |node|
        node.replace(node.children)
      end

      doc
    end
  end

end
