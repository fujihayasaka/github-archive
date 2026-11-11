# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    module Metadata
      class RevokedComponent < BaseComponent
        private

        sig { override.returns(Symbol) }
        def header_background_scheme = :attention

        sig { override.returns(T.nilable(String)) }
        def header_content
          render(Primer::Box.new(display: :flex, justify_content: :space_between)) do
            safe_join([
              render(Primer::Beta::Text.new(tag: :span, float: :left, test_selector: "header-status-content")) do
                if metadata_record.denied_at
                  safe_join([
                    content_tag(:strong, "Revoked"),
                    "on #{metadata_record.denied_at.strftime('%B %d, %Y')}",
                  ], " ")
                else
                  content_tag(:strong, "Revoked")
                end
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
            content_tag(:p) { "Your academic status requires reverification to continue your GitHub Education benefits and restore Copilot and Partner offers." },
            content_tag(:p) { "Your GitHub access will remain uninterrupted if you are successfully reverified within 30 days of revocation." },
            content_tag(:p) { "We apologize for any inconvenience." },
          ])
        end
      end
    end
  end
end
