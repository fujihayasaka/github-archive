# typed: true
# frozen_string_literal: true


module Localization
  module AzureTranslations
    module Filters
      # This is part of a html processor that changes html prior to its translation
      # This filter removes the id of the source html so it does not get duplicated
      # when the translation is appended to the DOM.
      class IdRemoverFilter < ::HTML::Pipeline::Filter
        def call
          doc.search("[id]").each do |node|
            node.remove_attribute("id")
          end

          doc
        end
      end
    end
  end
end
