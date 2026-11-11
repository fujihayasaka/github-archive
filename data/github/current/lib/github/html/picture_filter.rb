# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # This filter wraps picture elements in a themed-picture so that we can update
  # the theming on the client side after it's loaded to match the GitHub theme.
  class PictureFilter < Filter

    def call
      doc.search("picture").each do |element|
        nest_element(element, "themed-picture")
      end

      doc
    end

    def nest_element(element, tag_name, attrs = {})
      el = doc.document.create_element(tag_name, attrs)
      el.add_child(element.dup)
      element.replace(el)
      el
    end
  end
end
