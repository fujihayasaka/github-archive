# typed: true
# frozen_string_literal: true

module StructuredTemplates
  module Elements
    class MarkdownComponent < StructuredTemplates::Elements::BaseComponent
      def call
        render(Primer::Beta::Markdown.new(font_size: 5, test_selector: "issue-form-markdown", mb: 3)) { markdown }
      end

      private

      def markdown
        GitHub::Goomba::MarkdownPipeline.to_html(element.value)
      end
    end
  end
end
