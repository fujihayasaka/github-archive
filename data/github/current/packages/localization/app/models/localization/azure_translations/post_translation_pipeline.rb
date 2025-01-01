# typed: true
# frozen_string_literal: true

module Localization
  module AzureTranslations
    class PostTranslationPipeline < ::HTML::Pipeline
      DEFAULT_FILTERS = [
        Filters::NoTranslateRestorerFilter
      ]

      def initialize(filters = DEFAULT_FILTERS, context = {})
        super(filters, context)
      end
    end
  end
end
