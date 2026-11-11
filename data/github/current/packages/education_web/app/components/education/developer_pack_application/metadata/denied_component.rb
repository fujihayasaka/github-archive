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
                  content_tag(:strong, "Rejected"),
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
            content_tag(:strong) do
              "We were unfortunately not able to verify your academic status. Please address the following issues and apply again."
            end,
            content_tag(:br),
            render(Primer::Beta::Markdown.new(font_size: 5)) do
              GitHub::Goomba::MarkdownPipeline.to_html(metadata_record.rejection_reason)
            end,
            content_tag(:br),
            safe_join([
              "Visit ",
              link_to("our EDU community", "https://github.com/orgs/community/discussions/111352", target: "_blank", rel: "noopener noreferrer"),
              " for FAQs and tips.",
            ]),
          ])
        end
      end
    end
  end
end
