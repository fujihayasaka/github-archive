# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Legal
      class SectionComponent < ApplicationComponent
        def initialize(section:)
          @section = section
        end

        def render?
          @section.present? && component.render?
        end

        def call
          content_tag(:div, render(component), class: "mb-5 mb-md-6")
        end

        private

        memoize def component
          begin
            case @section.content_type.id
            when "component_section_document_list"
              Site::Contentful::Legal::DocumentListComponent.new(
                preamble: @section.preamble,
                title: @section.title,
                documents: @section.documents,
                postamble: @section.postamble
              )
            when "component_simple_rich_text"
              Site::Contentful::SimpleRichTextComponent.new(text: @section.text, classes: %w(f4-mktg color-fg-muted))
            end
          end
        end
      end
    end
  end
end
