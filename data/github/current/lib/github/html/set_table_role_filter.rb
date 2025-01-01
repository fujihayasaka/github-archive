# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # Adds `table` role to `<table>` elements generated with markdown.
  class SetTableRoleFilter < Filter
    def call
      doc.search("table").each do |element|
        call_element(element)
      end

      doc.to_html
    end

    def call_element(element)
      element["role"] = "table"

      element
    end
  end
end
