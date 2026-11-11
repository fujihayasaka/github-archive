# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    module Metadata
      class DeniedComponent < BaseComponent
        private

        sig { override.returns(Symbol) }
        def header_background_scheme = :danger

        sig { override.returns(T.nilable(String)) }
        def header_content
          render(Primer::Box.new(display: :flex, justify_content: :space_between)) do
            safe_join([
              render(Primer::Beta::Text.new(tag: :span, float: :left, test_selector: "header-status-content")) do
                safe_join([
                  content_tag(:strong, "Denied"),
                  "on #{metadata_record.denied_at.strftime('%B %d, %Y')}",
                ], " ")
              end,
              render(Primer::Beta::Text.new(tag: :span, float: :right, test_selector: "header-type-content")) do
                safe_join([
                  content_tag(:strong, "Application Type:"),
                  metadata_record.application_type.capitalize,
                ], " ")
              end,
            ])
          end
        end

        sig { override.returns(String) }
        def body_content
          safe_join([
            content_tag(:strong, "Reason(s):"),
            render(Primer::Beta::Markdown.new(font_size: 5)) do
              GitHub::Goomba::MarkdownPipeline.to_html(metadata_record.rejection_reason)
            end,
          ])
        end
      end
    end
  end
end
