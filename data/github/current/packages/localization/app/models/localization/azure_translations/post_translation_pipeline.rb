# typed: true
# frozen_string_literal: true

require "github/html/sanitization_filter"

module Localization
  module AzureTranslations
    class PostTranslationPipeline < ::HTML::Pipeline
      DEFAULT_FILTERS = [
        Filters::NoTranslateRestorerFilter,
        # Azure is called with textType: "html" so attacker markup in a discussion comment
        # survives the round-trip. Sanitize before this reaches `innerHTML` on the client.
        GitHub::HTML::SanitizationFilter,
      ]

      def initialize(filters = DEFAULT_FILTERS, context = {})
        super(filters, context)
      end
    end
  end
end
