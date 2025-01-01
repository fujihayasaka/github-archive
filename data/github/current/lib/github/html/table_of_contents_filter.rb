# typed: true
# frozen_string_literal: true

module GitHub::HTML
  class TableOfContentsFilter < Filter
    PUNCTUATION_REGEXP = /[^\p{Word}\- ]/u

    # The icon that will be placed next to an anchored rendered markdown header
    def anchor_icon
      attrs = {
        "aria-hidden": "true",
        class: "octicon octicon-link",
      }
      context[:anchor_icon] || ActionController::Base.helpers.content_tag(:span, "", attrs)
    end

    def call
      seen_anchors = Set.new
      doc.css("h1, h2, h3, h4, h5, h6").each do |node|
        text = node.text
        id = text.mb_chars.downcase.to_s
        id.gsub!(PUNCTUATION_REGEXP, "") # remove punctuation
        id.gsub!(" ", "-") # replace spaces with dash

        anchor = ""
        uniq = 0
        loop do
          suffix = uniq > 0 ? "-#{uniq}" : ""
          anchor = "#{id}#{suffix}"
          uniq += 1
          break if !seen_anchors.include?(anchor)
        end

        if header_content = node.children.first
          seen_anchors << anchor
          header_content.add_previous_sibling(%Q{<a id="#{anchor}" class="anchor" aria-hidden="true" href="##{anchor}">#{anchor_icon}</a>})
        end
      end
      doc
    end
  end
end
