# typed: true
# frozen_string_literal: true

module Localization
  module AzureTranslations
    class PreTranslationPipeline < ::HTML::Pipeline
      DEFAULT_FILTERS = [
        Filters::IdRemoverFilter,
        Filters::NoTranslateRemoverFilter
      ]

      def initialize(filters = DEFAULT_FILTERS, context = {})
        super(filters, context)
      end
    end
  end
end
