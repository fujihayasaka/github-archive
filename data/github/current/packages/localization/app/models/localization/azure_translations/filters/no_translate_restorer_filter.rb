# typed: true
# frozen_string_literal: true

module Localization
  module AzureTranslations
    module Filters
      # This filter restores the DOM fragments removed by the NoTranslateRestorerFilter,
      # after a translation is performed.
      class NoTranslateRestorerFilter < ::HTML::Pipeline::Filter
        def call
          each_placeholder do |id, content|
            restore_node(doc.at_css("##{id}"), content)
          end

          doc
        end

        private

        def each_placeholder(&block)
          result.fetch(:removed_no_translate, {}).each(&block)
        end

        def restore_node(node, content)
          if node
            node.replace(content)
          end
        end
      end
    end
  end
end
