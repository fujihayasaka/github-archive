# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Legal
      class DocumentListComponent < ApplicationComponent
        def initialize(preamble: nil, title: nil, documents: [], postamble: nil)
          @preamble = preamble
          @title = title
          @documents = documents
          @postamble = postamble
        end

        def render?
          @documents.present?
        end

        def document_links
          @documents.map do |document|
            Site::Contentful::Legal::DocumentLinkComponent.new(
              title: document.title,
              href: document.try(:url) || document.try(:path),
              subtitle: document.try(:subtitle),
              external: document.content_type.id == "resource_external_document"
            )
          end
        end

        def list_classes
          class_names("list-style-none", { "mb-2" => @postamble.present? })
        end
      end
    end
  end
end
