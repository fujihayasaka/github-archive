# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    module Metadata
      class ApprovedComponent < BaseComponent
        private

        sig { override.returns(Symbol) }
        def header_background_scheme = :success

        sig { override.returns(T.nilable(String)) }
        def header_content
          render(Primer::Box.new(display: :flex, justify_content: :space_between)) do
            safe_join([
              render(Primer::Beta::Text.new(tag: :span, float: :left, test_selector: "header-status-content")) do
                safe_join([
                  content_tag(:strong, "Approved"),
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
            content_tag(:p) { "Your academic status has been verified. Congratulations!" },
            content_tag(:p) do
              safe_join([
                "Your academic benefits, including Partner offers, will become available within ",
                "72 hours of your verification."
              ])
            end,
            content_tag(:p) do
              safe_join([
                "Once the benefits become available, you will be able to access the Students Developer Pack offers ",
                link_to("here", "https://education.github.com/pack", class: "Link--inTextBlock"),
                ".",
              ])
            end,
            content_tag(:p) do
              safe_join([
                "To redeem your Copilot Pro coupon, please sign up via this ",
                link_to("link", "https://github.com/github-copilot/free_signup", class: "Link--inTextBlock", "data-test-selector": "student-copilot-link"),
                ".",
              ])
            end,
            content_tag(:p) { "We hope you enjoy your GitHub Education benefits." },
            expiration_content,
          ])
        end

        sig { returns(String) }
        def faculty_body_content
          safe_join([
            content_tag(:p) { "Your academic status has been verified. Congratulations!" },
            content_tag(:p) do
              safe_join([
                "Your academic benefits will become available within ",
                "72 hours of your verification."
              ])
            end,
            content_tag(:p) do
              safe_join([
                "Once the benefits become available, you will be able to upgrade your organizations to GitHub Teams via your ",
                link_to("GitHub Education dashboard", "https://education.github.com/globalcampus/teacher", class: "Link--inTextBlock", "data-test-selector": "faculty-dashboard-link"),
                ".",
              ])
            end,
            content_tag(:p) do
              safe_join([
                "To redeem your Copilot Pro coupon, please sign up via this ",
                link_to("link", "https://github.com/github-copilot/free_signup", class: "Link--inTextBlock"),
                ".",
              ])
            end,
            content_tag(:p) { "We hope you enjoy your GitHub Education benefits." },
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
