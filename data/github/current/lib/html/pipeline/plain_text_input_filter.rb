module HTML
  class Pipeline
    # Simple filter for plain text input. HTML escapes the text input and wraps it
    # in a div.
    class PlainTextInputFilter < TextFilter
      def call
        "<div>#{ERB::Util.force_escape(@text)}</div>"
      end
    end
  end
end
