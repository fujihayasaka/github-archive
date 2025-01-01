# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      class DeveloperPackApplicationComponent < ApplicationComponent
        sig { params(user: User, utm_source: T.nilable(String), utm_content: T.nilable(String)).void }
        def initialize(user:, utm_source: nil, utm_content: nil)
          @user = user
          @utm_source = utm_source
          @utm_content = utm_content
        end

        sig { returns(String) }
        def call
          content_tag(
            "turbo-frame",
            id: "dev-pack-form",
            src: new_settings_education_developer_pack_application_path(utm_source:, utm_content:),
            loading: :lazy,
            data: test_selector_hash("dev-pack-form"),
          ) do
            content_tag(
              :div,
              render(
                Primer::Beta::Spinner.new(
                  size: :large,
                  sr_text: "Gathering available school information...",
                ),
              ),
              class: "text-center",
            )
          end
        end

        private

        sig { returns(User) }
        attr_reader :user

        sig { returns(T.nilable(String)) }
        attr_reader :utm_source

        sig { returns(T.nilable(String)) }
        attr_reader :utm_content

        sig { returns(T::Boolean) }
        def render?
          feature_enabled_globally_or_for_user?(feature_name: "education-dev-pack-application", subject: user)
        end
      end
    end
  end
end
