# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      module DeveloperPackApplication
        class InitialForm < BaseForm
          include GitHub::Memoizer
          include ::Education::DeveloperPackApplication::SchoolHelper

          FORM_FIELDS_FOR_THIS_PAGE = [
            Field.new(name: :application_type, required: true),
            Field.new(name: :school_name, required: true),
            Field.new(name: :school_email, required: true),
            Field.new(name: :new_school),
          ].freeze

          form do |initial_form|
            T.bind(self, InitialForm)

            initial_form.radio_button_group(
              name: :application_type,
              label: "Select your role in education: *",
              required: true,
              validation_message: form_errors[:application_type],
            ) do |radio_group|
              radio_group.radio_button(
                value: "faculty",
                label: "Teacher",
                ml: 2,
                classes: "js-dev-pack-application-type-selection",
              )
              radio_group.radio_button(
                value: "student",
                label: "Student",
                ml: 2,
                classes: "js-dev-pack-application-type-selection",
              )
            end

            initial_form.text_field(
              name: :school_name,
              classes: "d-none",
              label: nil,
            )

            initial_form.select_list(
              name: :school_email,
              id: "js-developer-pack-application-email-selection-container",
              label: "What is your school email address?",
              required: true,
              caption: school_email_caption,
              validation_message: form_errors[:school_email],
            ) do |select|
              verified_emails.each do |email|
                select.option(value: email, label: email, selected: email == suggested_school_email)
              end
            end

            initial_form.hidden(name: :latitude, id: latitude_input_id)
            initial_form.hidden(name: :longitude, id: longitude_input_id)
            initial_form.hidden(name: :location_shared, id: location_shared_input_id)

            existing_fields_to_forward(form: initial_form)
            initial_form.text_field(
              name: :browser_location,
              classes: "d-none",
              label: nil,
            )
            submit_button(
              form: initial_form,
              id: continue_button_id,
              disabled: true,
            )
          end

          private

          def continue_button_id = "js-developer-pack-application-submit-button"
          def latitude_input_id = "js-developer-pack-application-latitude-input"
          def longitude_input_id = "js-developer-pack-application-longitude-input"
          def location_shared_input_id = "js-developer-pack-application-location-shared-input"

          memoize def verified_emails
            user.emails.verified.pluck(:email)
          end

          def school_email_caption
            safe_join([
              content_tag(:p, class: "text-small color-fg-muted mt-1") do
                safe_join([
                  "Have a different email address you use with your school?",
                  link_to(
                    "Add it here.",
                    Rails.application.routes.url_helpers.settings_email_preferences_path,
                    data: { turbo: false },
                  ),
                ], " ")
              end,
              link_to(
                "Privacy Policy",
                Rails.application.routes.url_helpers.site_privacy_path,
                class: "text-small mt-2",
                data: { turbo: false },
              ),
            ])
          end

          def suggested_school_email
            return if suggested_school.blank?

            verified_emails.find do |email|
              suggested_school.email_domains.find do |email_domain|
                email.ends_with?(email_domain.domain)
              end
            end
          end

          def suggested_school
            return if suggested_schools.blank?

            suggested_schools.first
          end

          def suggested_school_banner_content
            render(
              Primer::Alpha::Banner.new(
                scheme: :success,
                h: :fit,
                my: 2,
                icon: "mortar-board",
              ),
            ) do
              safe_join(
                [
                  render(
                    Primer::Box.new(
                      mb: 5,
                      h: :fit,
                    ),
                  ) do
                    safe_join(
                      [
                        "You have verified the email address ",
                        content_tag(:strong, suggested_school_email),
                        " on your GitHub account. That academic domain is associated with the school ",
                        content_tag(:strong, suggested_school.name),
                        ".",
                      ],
                    )
                  end,
                  render(
                    Primer::Beta::Button.new(
                      size: :small,
                      mb: 2,
                      bottom: 0,
                      id: "js-suggested-school-select-button",
                      data: {
                        school_name: suggested_school["name"],
                        selected_school_id: suggested_school["school_id"],
                        two_factor_required: user_needs_2fa_turned_on?(
                          school: suggested_school,
                          user_has_two_factor_auth_enabled: user.two_factor_authentication_enabled?,
                        ),
                        override_distance_limit: suggested_school["override_distance_limit"],
                        camera_required: !school_allows_file_uploads?(school: suggested_school),
                        email_domains: email_domains(school: suggested_school),
                        user_too_far_from_school: user_too_far_from_school?(school: suggested_school),
                        user_has_email_for_school: true,
                      },
                    ).with_content("Select this school"),
                  ),
                ],
              )
            end
          end

          def chosen_school_has_allowlisted_domains_banner_content
            render(
              Primer::Alpha::Banner.new(
                scheme: :warning,
                h: :fit,
                my: 2,
                icon: "alert",
                hidden: true,
                id: "js-chosen-school-has-allowlisted-domains-banner",
              ),
            ) do
              render(
                Primer::Box.new(
                  mb: 5,
                  h: :fit,
                ),
              ) do
                safe_join(
                  [
                    content_tag(:p) do
                      safe_join(
                        [
                          "We require applicants of",
                          content_tag(:strong, "", id: "js-chosen-school-has-allowlisted-domains-banner-school-name"),
                          "to use one of these school-issues email addresses to apply:",
                        ],
                        " ",
                      )
                    end,
                    content_tag(:ul) do
                      content_tag(:li, "", id: "js-chosen-school-first-allowlisted-domain")
                    end,
                    content_tag(:ul, "", id: "js-chosen-school-domains-list", hidden: true),
                    render(Primer::Beta::Button.new(scheme: :link, mt: 2, id: "js-chosen-school-domains-show-more").with_content("Show more")),
                    content_tag(:p, class: "mt-2") do
                      safe_join(
                        [
                          "Please",
                          link_to(
                            Rails.application.routes.url_helpers.settings_email_preferences_path,
                            data: { turbo: false },
                          ) do
                            safe_join(
                              [
                                "add and verify your",
                                content_tag(:strong, "school-issued email address"),
                              ],
                              " ",
                            )
                          end,
                          "in your account settings -- or a contact email if you do not have one.",
                          "Once your email is verified, you can try applying again.",
                        ],
                        " ",
                      )
                    end,
                  ],
                )
              end
            end
          end
        end
      end
    end
  end
end
