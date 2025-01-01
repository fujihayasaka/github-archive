# typed: true
# frozen_string_literal: true

module Localization
  module AzureTranslations
    module Filters
      # This is part of a html processor that changes html prior to its translation
      # This filter removes parts of a DOM fragment that should not be translated.
      # By doing so, the translation request gets smaller, and that is importatn so
      # we don't surpass the request body size limit imposed by the translation API.
      #
      # After the fragment is translted, the NoTranslateRestorerFilter restores the DOM
      # parts removed by this filter.
      #
      # @see https://docs.microsoft.com/en-us/azure/cognitive-services/translator/prevent-translation
      class NoTranslateRemoverFilter < ::HTML::Pipeline::Filter
        def call
          doc.search(".notranslate").each do |node|
            insert_placeholder(node)
          end

          doc
        end

        private

        def insert_placeholder(node)
          id = next_id
          collect_context(id, node)
          node.inner_html = "<span id=\"#{id}\"></span>"
        end

        # TPH stands for Translation Placeholder
        def next_id
          "tph_#{SecureRandom.uuid}"
        end

        def collect_context(id, node)
          result[:removed_no_translate] ||= {}
          result[:removed_no_translate][id] = node.inner_html
        end
      end
    end
  end
end
