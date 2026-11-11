# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    module Metadata
      class CouponAppliedComponent < BaseComponent
        private

        sig { override.returns(Symbol) }
        def header_background_scheme = :success

        sig { override.returns(T.nilable(String)) }
        def header_content
          render(Primer::Box.new(display: :flex, justify_content: :space_between)) do
            safe_join([
              render(Primer::Beta::Text.new(tag: :span, float: :left, test_selector: "header-status-content")) do
                safe_join([
                  content_tag(:strong, "Verified (benefits available)"),
                  "on #{metadata_record.approved_at.strftime('%B %d, %Y')}",
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
          if metadata_record.student?
            student_body_content
          else
            faculty_body_content
          end
        end

        sig { returns(String) }
        def student_body_content
          safe_join([
            content_tag(:p) { "Congratulations!" },
            content_tag(:p) { "Your academic benefits, including Partner offers, are now available." },
            content_tag(:p) do
              safe_join([
                "You can access Student Developer Pack offers ",
                link_to("here", "https://education.github.com/pack", class: "Link--inTextBlock"),
                " and redeem Copilot via this ",
                link_to("link", "https://github.com/github-copilot/free_signup", class: "Link--inTextBlock", "data-test-selector": "student-copilot-link"),
                ".",
              ])
            end,
            content_tag(:p) { "We can't wait to see what you build with GitHub!" },
            expiration_content,
          ])
        end

        sig { returns(String) }
        def faculty_body_content
          safe_join([
            content_tag(:p) { "Your academic status has been verified. Congratulations!" },
            content_tag(:p) do
              safe_join([
                "Your academic benefits are now available."
              ])
            end,
            content_tag(:p) do
              safe_join([
                "You can upgrade your organizations to GitHub Teams via your ",
                link_to("GitHub Education dashboard", "https://education.github.com/globalcampus/teacher", class: "Link--inTextBlock", "data-test-selector": "faculty-dashboard-link"),
                ".",
              ])
            end,
            content_tag(:p) do
              safe_join([
                "To redeem Copilot, please sign up via this ",
                link_to("link", "https://github.com/github-copilot/free_signup", class: "Link--inTextBlock"),
                ".",
              ])
            end,
            content_tag(:p) { "We can't wait to see what you build with GitHub!" },
            expiration_content,
          ])
        end

        sig { returns(String) }
        def expiration_content
          if metadata_record.expires_at.present?
            content_tag(:p) do
              safe_join([
                "Your benefits will expire on ",
                content_tag(:strong, T.must(metadata_record.expires_at).strftime("%B %d, %Y")),
                "."
              ])
            end
          else
            ""
          end
        end
      end
    end
  end
end
