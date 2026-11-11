# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    module Metadata
      class ExpiredComponent < BaseComponent
        private

        sig { override.returns(Symbol) }
        def header_background_scheme = :done

        sig { override.returns(T.nilable(String)) }
        def header_content
          render(Primer::Box.new(display: :flex, justify_content: :space_between)) do
            safe_join([
              render(Primer::Beta::Text.new(tag: :span, float: :left, test_selector: "header-status-content")) do
                safe_join([
                  content_tag(:strong, "Expired"),
                  "on #{T.must(metadata_record.expires_at).strftime('%B %d, %Y')}",
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
          content_tag(:p) do
            safe_join([
              "You are no longer receiving the benefits of the Developer Pack.",
              "Please reapply if you believe you are still eligible.",
            ], " ")
          end
        end
      end
    end
  end
end
