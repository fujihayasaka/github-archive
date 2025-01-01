# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # Transcode all incoming content to UTF-8. Html pipeline outputs html,
  # which at GitHub should always be UTF-8.
  class UTF8Filter < Filter
    include GitHub::UTF8

    def initialize(doc, context = nil, result = nil)
      if doc.is_a?(String)
        @input = utf8(doc)
      else
        @input = doc
      end
      if context[:blob] && context[:blob].data.is_a?(String)
        context[:blob].data = utf8(context[:blob].data)
      end
      super @input, context, result
    end

    def call
      # NOOP
      @input
    end
  end
end
